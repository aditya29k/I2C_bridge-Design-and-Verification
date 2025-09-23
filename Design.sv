`timescale 1ns/1ps

`ifndef clk_frequency
	`define clk_frequency 40000000 // 40MHz
`endif

`ifndef i2c_frequency
	`define i2c_frequency 100000 // 100KHz
`endif

`ifndef clk_count
	`define clk_count (`clk_frequency/`i2c_frequency) //400
`endif

`ifndef clk4
	`define clk4 (`clk_count/4) // 100
`endif

module top(
  input clk, rst, 
  input op,
  input [7:0] din,
  input [6:0] addr,
  output [7:0] dout,
  input start_bit,
  output done, busy, ack_arr,
  inout [1:0] sda_bus,
  output bus_val
);
  
  wire [1:0] pulse;
  wire [8:0] count;
  
  wire scl;
  
  wire ack_err1, ack_err2;
  wire done1, done2;

  wire sda;
  
  pulse_gen pulse_0 (.clk(clk), .rst(rst), .pulse(pulse), .busy(busy), .count(count));
  
  i2c_master master (.clk(clk), .rst(rst), .din(din), .addr(addr), .dout(dout), .start_bit(start_bit), .done(done1), .busy(busy), .ack_err(ack_err1), .scl(scl), .sda(sda), .op(op));
  
  i2c_bridge bridge (.clk(clk), .busy(busy), .rst(rst), .sda(sda), .scl(scl), .sda_bus(sda_bus), .bridge_ack_err(ack_err2), .done(done2), .bus_val(bus_val));
  
  assign done = done1||done2;
  assign ack_err = ack_err1|ack_err2;
  
endmodule

module pulse_gen(
  input clk, rst,
  input busy,
  output reg [1:0] pulse,
  output reg [8:0] count
);
  
  always@(posedge clk) begin
    if(rst) begin
      pulse <= 0;
      count <= 0;
    end
    else if(busy == 1'b0) begin 
      pulse <= 0;
      count <= 0;
    end
    else if(count == `clk4*1 - 1) begin // 0-99
      pulse <= 1;
      count <= count + 1;
    end
    else if(count == `clk4*2 - 1) begin // 100-199
      pulse <= 2;
      count <= count + 1;
    end
    else if(count == `clk4*3 - 1) begin // 200-299
      pulse <= 3;
      count <= count + 1;
    end
    else if(count == `clk4*4 - 1) begin // 300-399
      pulse <= 0;
      count <= 0;
    end
    else begin
      count <= count + 1;
    end
  end
  
endmodule

module i2c_bridge(
  input clk, rst, // inputs for pulse_gen
  
  input busy,
  inout sda, 
  input scl, // from real master
  
  inout [1:0] sda_bus,
  output reg bridge_ack_err, 
  output reg bus_val,
  output reg done // use in verification
);
  
  reg [1:0] pulse;
  reg [8:0] count;
  
  pulse_gen p0 (.clk(clk), .rst(rst), .busy(busy), .pulse(pulse), .count(count));
  
  reg recv_ack;
  reg wr_en_m, wr_en_s;
  
  localparam vaddr = 7'h2a; // virtual address
  localparam raddr = 7'h11; // real address
  
  reg sda_temp;
  
  integer data_count;
  
  reg [7:0] temp_addr;
  reg [7:0] temp_data_master;
  reg [7:0] temp_data_slave;
  reg [1:0] sda_bus_temp;
  
  typedef enum {IDLE, START, MASTER_SEND_ADDR, BRIDGE_SEND_ADDR, BRIDGE_RECV_ACK, BRIDGE_SEND_ACK, MASTER_WRITE, BRIDGE_WRITE, BRIDGE_WRITE_ACK, MASTER_WRITE_ACK, SLAVE_SEND_READ, BRIDGE_SEND_READ, MASTER_READ_ACK, BRIDGE_READ_ACK, STOP} states;
  states state;
  
  always@(posedge clk) begin
    if(rst) begin
      temp_addr <= 0;
      bus_val <= 1'b0;
      data_count <= 0;
      wr_en_m <= 1'b0;
      wr_en_s <= 1'b0;
      recv_ack <= 1'b0;
      bridge_ack_err <= 0;
      sda_bus_temp <= 2'b00;
      temp_data_master <= 0;
      temp_data_slave <= 0;
      state <= IDLE;
      done <= 1'b0;
      //busy <= 1'b0;
      sda_temp <= 1'b1;
    end
    else begin
      case(state)
        
        IDLE: begin
          temp_addr <= 0;
          sda_temp <= 1'b1;
          sda_bus_temp <= 2'b11;
          bus_val <= 1'b0; // default bus at channel 0
          data_count <= 0;
          {wr_en_m, wr_en_s} <= 2'b00;
          recv_ack <= 1'b0;
          temp_data_master <= 0;
      	  temp_data_slave <= 0;
          done <= 1'b0;
          if(scl == 1'b1 && sda == 1'b0) begin // Start Condition
            state <= START;
            //busy <= 1'b1;
          end
          else begin
            state <= IDLE;
            //busy <= 1'b0;
          end
        end
        
        START: begin
          if(count == `clk4*4 - 1) begin
            state <= MASTER_SEND_ADDR;
          end
          else begin
            state <= START;
          end
        end
        
        MASTER_SEND_ADDR: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
              end
              1: begin
              end
              2: begin
                temp_addr[7:0] <= (count == `clk4*2) ? {temp_addr[6:0], sda}:temp_addr[7:0]; // MSB first temp[7] is operation
              end
              3: begin
              end
            endcase
            if(count == `clk4*4 - 1) begin
              data_count <= data_count + 1;
              state <= MASTER_SEND_ADDR;
            end
            else begin
              state <= MASTER_SEND_ADDR;
            end
          end
          else begin
            if(temp_addr[6:0] == vaddr) begin
              bus_val <= 1'b1;
              temp_addr[6:0] <= raddr;
            end
            else begin
              bus_val <= 1'b0;
            end
            data_count <= 0;
            state <= BRIDGE_SEND_ADDR; 
            wr_en_s <= 1'b1;
          end
        end
        
        BRIDGE_SEND_ADDR: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
              end
              1: begin
                if(bus_val) begin
                  sda_bus_temp[1] <= temp_addr[7-data_count];
                end
                else begin
                  sda_bus_temp[0] <= temp_addr[7-data_count];
                end
              end
              2: begin
              end
              3: begin
              end
            endcase
            if(count == `clk4*4 - 1) begin
              data_count <= data_count + 1;
              state <= BRIDGE_SEND_ADDR;
            end
            else begin
              state <= BRIDGE_SEND_ADDR;
            end
          end
          else begin
            wr_en_s <= 1'b0;
            state <= BRIDGE_RECV_ACK;
            data_count <= 0;
          end
        end
        
        BRIDGE_RECV_ACK: begin
          case(pulse)
            0: begin
            end
            1: begin
            end
            2: begin
              recv_ack <= (bus_val)? sda_bus[1]:sda_bus[0];
            end
            3: begin
              recv_ack <= recv_ack;
            end
          endcase
          if(count == `clk4*4 - 1) begin
            if(!recv_ack) begin // Receive NACK
              state <= BRIDGE_SEND_ACK;
              wr_en_m <= 1'b1;
            end
            else begin
              state <= STOP;
              bridge_ack_err <= 1'b1;
            end
          end
          else begin
            state <= BRIDGE_RECV_ACK;
          end
        end
        
        BRIDGE_SEND_ACK: begin
          case(pulse) 
            0: begin
            end
            1: begin
              sda_temp <= 1'b0; // NACK
            end
            2: begin
            end
            3: begin
            end
          endcase
          if(count == `clk4*4 - 1) begin
            wr_en_m <= 1'b0;
            if(temp_addr[7] == 1'b0) begin // WRITE MODE
              state <= MASTER_WRITE;
              wr_en_m <= 1'b0;
            end
            else begin // READ MODE
              state <= SLAVE_SEND_READ;
              wr_en_s <= 1'b0;
            end
          end
          else begin
            state <= BRIDGE_SEND_ACK;
          end
        end
        
        MASTER_WRITE: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
              end
              1: begin
              end
              2: begin
                temp_data_master[7:0] <= (count == `clk4*2) ? {temp_data_master[6:0], sda}:temp_data_master[7:0];
              end
              3: begin
              end
            endcase
            if(count == `clk4*4 - 1) begin
              data_count <= data_count + 1;
              state <= MASTER_WRITE;
            end
            else begin
              state <= MASTER_WRITE;
            end
          end
          else begin
            wr_en_s <= 1'b1;
            state <= BRIDGE_WRITE;
            data_count <= 0;
          end
        end
        
        BRIDGE_WRITE: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
              end
              1: begin
                if(bus_val) begin
                  sda_bus_temp[1] <= temp_data_master[7-data_count];
                end
                else begin
                  sda_bus_temp[0] <= temp_data_master[7-data_count];
                end
              end
              2: begin
              end
              3: begin
              end
            endcase
            if(count == `clk4*4 - 1) begin
              state <= BRIDGE_WRITE;
              data_count <= data_count + 1;
            end
            else begin
              state <= BRIDGE_WRITE;
            end
          end
          else begin
            state <= BRIDGE_WRITE_ACK;
            data_count <= 0;
            wr_en_s <= 0;
          end
        end
        
        BRIDGE_WRITE_ACK: begin
          case(pulse)
            0: begin
            end
            1: begin
            end
            2: begin
              recv_ack <= (bus_val)? sda_bus[1]:sda_bus[0];
            end
            3: begin
            end
          endcase
          if(count == `clk4*4 - 1) begin
            if(!recv_ack) begin
              state <= MASTER_WRITE_ACK;
              wr_en_m <= 1'b1;
            end
            else begin
              state <= STOP;
              bridge_ack_err <= 1'b1;
            end
          end
          else begin
            state <= BRIDGE_WRITE_ACK;
          end
        end
        
        MASTER_WRITE_ACK: begin
          case(pulse)
            0: begin
            end
            1: begin
              sda_temp <= 1'b0;
            end
            2: begin
            end
            3: begin
            end
          endcase
          if(count == `clk4*4 - 1) begin
            state <= STOP;
            wr_en_m <= 1'b0;
          end
          else begin
            state <= MASTER_WRITE_ACK;
          end
        end
        
        SLAVE_SEND_READ: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
              end
              1: begin
              end
              2: begin
                if(bus_val) begin
                  temp_data_slave[7:0] <= (count == `clk4*2) ? {temp_data_slave[6:0], sda_bus[1]}:temp_data_slave[7:0];
                end
                else begin
                  temp_data_slave[7:0] <= (count == `clk4*2) ? {temp_data_slave[6:0], sda_bus[0]}:temp_data_slave[7:0];
                end
              end
              3: begin
                temp_data_slave[7:0] <= temp_data_slave[7:0];
              end
            endcase
            if(count == `clk4*4 - 1) begin
              state <= SLAVE_SEND_READ;
              data_count <= data_count + 1;
            end
            else begin
              state <= SLAVE_SEND_READ;
            end
          end
          else begin
            state <= BRIDGE_SEND_READ;
            wr_en_m <= 1'b1;
            data_count <= 0;
          end
        end
        
        BRIDGE_SEND_READ: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
              end
              1: begin
                sda_temp <= temp_data_slave[7-data_count];
              end
              2: begin
              end
              3: begin
              end
            endcase
            if(count == `clk4*4 - 1) begin
              state <= BRIDGE_SEND_READ;
              data_count <= data_count + 1;
            end
            else begin
              state <= BRIDGE_SEND_READ;
            end
          end
          else begin
            wr_en_m <= 1'b0;
            state <= MASTER_READ_ACK;
            data_count <= 0;
          end
        end
        
        MASTER_READ_ACK: begin
          case(pulse) 
            0: begin
            end
            1: begin
            end
            2: begin
              recv_ack <= sda;
            end
            3: begin
            end
          endcase
          if(count == `clk4*4 - 1) begin
            if(recv_ack == 1'b1) begin // Master send's positive acknowledgement
              state <= BRIDGE_READ_ACK;
              wr_en_s <= 1'b1;
            end
            else begin
              state <= STOP;
              bridge_ack_err <= 1'b1;
            end
          end
          else begin
            state <= MASTER_READ_ACK;
          end
        end
        
        BRIDGE_READ_ACK: begin
          case(pulse)
            0: begin
            end
            1: begin
              if(bus_val) begin
                sda_bus_temp[1] <= 1'b1;
              end
              else begin
                sda_bus_temp[0] <= 1'b1;
              end
            end
            2: begin
            end
            3: begin
            end
          endcase
          if(count == `clk4*4 - 1) begin
            state <= STOP;
            wr_en_s <= 1'b0;
          end
          else begin
            state <= BRIDGE_READ_ACK;
          end
        end
        
        STOP: begin
          if(count == `clk4*4 - 1) begin
            state <= IDLE;
            //busy <= 1'b0;
            done <= 1'b1;
          end
          else begin
            state <= STOP;
          end
        end
        
      endcase
    end
  end
  
  assign sda = (wr_en_m)? sda_temp:1'bz;
  assign sda_bus[0] = (wr_en_s) ? sda_bus_temp[0]:1'bz;
  assign sda_bus[1] = (wr_en_s) ? sda_bus_temp[1]:1'bz;
  
endmodule

module i2c_master(
  input clk, rst, op,
  input [7:0] din,
  input [6:0] addr,
  inout sda,
  output scl,
  output reg ack_err, busy, done,
  input start_bit, 
  output [7:0] dout
);
  
  reg [1:0] pulse;
  reg [8:0] count;
  
  pulse_gen p1 (.clk(clk), .rst(rst), .busy(busy), .pulse(pulse), .count(count));
  
  // FSM for Master
  
  reg recv_ack;
  reg wr_en;
  
  integer data_count;
  reg scl_temp;
  reg sda_temp;
  
  reg [7:0] temp_addr, temp_din, temp_dout;
  
  typedef enum {IDLE, START, ADDR, WAIT_ADDR, WAIT_ADDR_ACK, ADDR_ACK, WRITE, WAIT_WRITE, WAIT_WRITE_ACK, WRITE_ACK, WAIT_READ, READ, READ_ACK, WAIT_READ_ACK, STOP} states;
  states state;
  
  always@(posedge clk) begin
    if(rst) begin
      ack_err <= 1'b0;
      busy <= 1'b0;
      done <= 1'b0;
      recv_ack <= 1'b1; // DEFAULT HIGH
      wr_en <= 1'b0;
      data_count <= 0;
      scl_temp <= 1'b1;
      sda_temp <= 1'b1;
      temp_addr <= 0;
      temp_din <= 0;
      temp_dout <= 0;
      state <= IDLE;
    end
    else begin
      case(state)
        
        IDLE: begin
          ack_err <= 1'b0;
          done <= 1'b0;
          data_count <= 0;
          if(start_bit) begin
            busy <= 1'b1;
            state <= START;
            wr_en <= 1'b1;
            temp_addr <= {op,addr};
            temp_din <= din;
          end
          else begin
            busy <= 1'b0;
            state <= IDLE;
            wr_en <= 1'b0;
          end
        end
        
        START: begin
          case(pulse)
            0: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b1;
            end
            1: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b1;
            end
            2: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b0;
            end
            3: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b0;
            end
          endcase
          if(count == `clk4*4 - 1) begin
            state <= ADDR;
            scl_temp <= 1'b0;
          end
          else begin
            state <= START;
          end
        end
        
        ADDR: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
                scl_temp <= 1'b0;
                sda_temp <= 1'b0;
              end
              1: begin
                scl_temp <= 1'b0;
                sda_temp <= temp_addr[7-data_count];
              end
              2: begin
                scl_temp <= 1'b1;
              end
              3: begin
                scl_temp <= 1'b1;
              end
            endcase
            if(count == `clk4*4 - 1) begin
              state <= ADDR;
              scl_temp <= 1'b0;
              data_count <= data_count + 1;
            end
            else begin
              state <= ADDR;
            end
          end
          else begin
            data_count <= 0;
            state <= WAIT_ADDR;
            wr_en <= 1'b0;
          end
        end
        
        WAIT_ADDR: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
                scl_temp <= 1'b0;
              end
              1: begin
                scl_temp <= 1'b0;
              end
              2: begin
                scl_temp <= 1'b1;
              end
              3: begin
                scl_temp <= 1'b1;
              end
            endcase
            if(count == `clk4*4 - 1) begin
              state <= WAIT_ADDR;
              scl_temp <= 1'b0;
              data_count <= data_count + 1;
            end
            else begin
              state <= WAIT_ADDR;
            end
          end
          else begin
            state <= WAIT_ADDR_ACK;
            data_count <= 0;
          end
        end
        
        WAIT_ADDR_ACK: begin
          case(pulse)
            0: begin
              scl_temp <= 1'b0;
            end
            1: begin
              scl_temp <= 1'b0;
            end
            2: begin
              scl_temp <= 1'b1;
            end
            3: begin
              scl_temp <= 1'b1;
            end
          endcase
          if(count == `clk4*4 - 1) begin
            state <= ADDR_ACK;
            scl_temp <= 1'b0;
          end
          else begin
            state <= WAIT_ADDR_ACK;
          end
        end
        
        ADDR_ACK: begin
          case(pulse)
            0: begin
              scl_temp <= 1'b0;
            end
            1: begin
              scl_temp <= 1'b0;
            end
            2: begin
              scl_temp <= 1'b1;
              recv_ack <= sda;
            end
            3: begin
              scl_temp <= 1'b1;
            end
          endcase
          if(count == `clk4*4 - 1) begin
            scl_temp <= 1'b0;
            if((recv_ack == 1'b0) && (temp_addr[7] == 1'b0)) begin // WRITE
              wr_en <= 1'b1;
              state <= WRITE;
            end
            else if((recv_ack == 1'b0) && (temp_addr[7] == 1'b1)) begin // READ
              wr_en <= 1'b0;
              state <= WAIT_READ;
            end
            else begin
              state <= STOP;
              ack_err <= 1'b1;
              wr_en <= 1'b1;
            end
          end
          else begin
            state <= ADDR_ACK;
          end
        end
        
        WRITE: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
                scl_temp <= 1'b0;
                sda_temp <= 1'b1;
              end
              1: begin
                scl_temp <= 1'b0;
                sda_temp <= temp_din[7-data_count];
              end
              2: begin
                scl_temp <= 1'b1;
              end
              3: begin
                scl_temp <= 1'b1;
              end
            endcase
            if(count == `clk4*4 - 1) begin
              state <= WRITE;
              scl_temp <= 1'b0;
              data_count <= data_count + 1;
            end
            else begin
              state <= WRITE;
            end
          end
          else begin
            state <= WAIT_WRITE;
            wr_en <= 1'b0;
            data_count <= 0;
          end
        end
        
        WAIT_WRITE: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
                scl_temp <= 1'b0;
              end
              1: begin
                scl_temp <= 1'b0;
              end
              2: begin
                scl_temp <= 1'b1;
              end
              3: begin
                scl_temp <= 1'b0;
              end
            endcase
            if(count == `clk4*4 - 1) begin
              state <= WAIT_WRITE;
              data_count <= data_count + 1;
              scl_temp <= 1'b0;
            end
            else begin
              state <= WAIT_WRITE;
            end
          end
          else begin
            state <= WAIT_WRITE_ACK;
            data_count <= 0;
          end
        end
        
        WAIT_WRITE_ACK: begin
          case(pulse) 
            0: begin
              scl_temp <= 1'b0;
            end
            1: begin
              scl_temp <= 1'b0;
            end
            2: begin
              scl_temp <= 1'b1;
            end
            3: begin
              scl_temp <= 1'b1;
            end
          endcase
          if(count == `clk4*4 - 1) begin
            state <= WRITE_ACK;
            scl_temp <= 1'b0;
          end
          else begin
            state <= WAIT_WRITE_ACK;
          end
        end
        
        WRITE_ACK: begin
          case(pulse)
            0: begin
              scl_temp <= 1'b0;
            end
            1: begin
              scl_temp <= 1'b0;
            end
            2: begin
              scl_temp <= 1'b1;
              recv_ack <= sda;
            end
            3: begin
              scl_temp <= 1'b1;
            end
          endcase
          if(count == `clk4*4 - 1) begin
            if(recv_ack == 1'b0) begin
              state <= STOP;
              wr_en <= 1'b1;
            end
            else begin
              state <= STOP;
              ack_err <= 1'b1;
            end
          end
        end
        
        WAIT_READ: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
                scl_temp <= 1'b0;
              end
              1: begin
                scl_temp <= 1'b0;
              end
              2: begin
                scl_temp <= 1'b1;
              end
              3: begin
                scl_temp <= 1'b1;
              end
            endcase
            if(count == `clk4*4 - 1) begin
              state <= WAIT_READ;
              scl_temp <= 1'b0;
              data_count <= data_count + 1;
            end
            else begin
              state <= WAIT_READ;
            end
          end
          else begin
            state <= READ;
            data_count <= 0;
          end
        end
        
        READ: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
                scl_temp <= 1'b0;
              end
              1: begin
                scl_temp <= 1'b0;
              end
              2: begin
                scl_temp <= 1'b1;
                temp_dout[7:0] <= (count == `clk4*2) ? {temp_dout[6:0], sda}: temp_dout[7:0];
              end
              3: begin
                scl_temp <= 1'b1;
              end
            endcase
            if(count == `clk4*4 - 1) begin
              state <= READ;
              scl_temp <= 1'b0;
              data_count <= data_count + 1;
            end
            else begin
              state <= READ;
            end
          end
          else begin
            state <= READ_ACK;
            wr_en <= 1'b1;
            data_count <= 0;
          end
        end
        
        READ_ACK: begin
          case(pulse)
            0: begin
              scl_temp <= 1'b0;
              sda_temp <= 1'b0;
            end
            1: begin
              scl_temp <= 1'b0;
              sda_temp <= 1'b1; // Positive Acknowledgement
            end
            2: begin
              scl_temp <= 1'b1;
            end
            3: begin
              scl_temp <= 1'b1;
            end
          endcase
          if(count == `clk4*4 - 1) begin
            scl_temp <= 1'b0;
            wr_en <= 1'b0;
            state <= WAIT_READ_ACK;
          end
          else begin
            state <= READ_ACK;
          end
        end
        
        WAIT_READ_ACK: begin
          case(pulse)
            0: begin
              scl_temp <= 1'b0;
            end
            1: begin
              scl_temp <= 1'b0;
            end
            2: begin
              scl_temp <= 1'b1;
            end
            3: begin
              scl_temp <= 1'b1;
            end
          endcase
          if(count == `clk4*4 - 1) begin
            state <= STOP;
            wr_en <= 1'b1;
          end
          else begin
            state <= WAIT_READ_ACK;
          end
        end
        
        STOP: begin
          case(pulse) 
            0: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b0;
            end
            1: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b0;
            end
            2: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b1;
            end
            3: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b1;
            end
          endcase
          if(count == `clk4*4 - 1) begin
            state <= IDLE;
            busy <= 1'b0;
            done <= 1'b1;
            wr_en <= 1'b0;
          end
          else begin
            state <= STOP;
          end
        end
        
      endcase
    end
  end
  
  assign sda = (wr_en) ? sda_temp:1'bz;
  assign scl = scl_temp;
  assign dout = temp_dout;
  
endmodule
