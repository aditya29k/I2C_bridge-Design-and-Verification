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

interface i2c_intf;
  
  logic clk, rst, op;
  logic [7:0] din, dout;
  logic [6:0] addr;
  logic start_bit;
  logic ack_err, busy, done;
  wire [1:0] sda_bus;
  logic bus_val;
  
  logic wr_en_s0, wr_en_s1;
  logic data_0, data_1;
  
endinterface

class transaction;
  
  rand bit op;
  rand bit [7:0] din;
  rand bit [6:0] addr;
  bit change = 1'b0;
  
  constraint op_cons {
    op dist {0:=2, 1:=8};
  }
  
  constraint din_range {
    din inside {[0:15]};
    !(din inside {0});
  }
  
  constraint addr_range {
    addr inside {[1:127]};
    (change == 1'b1) -> (addr == 7'h2a); 
  }
  
endclass

module tb;
  
  i2c_intf intf();
  
  transaction trans;
  
  top DUT (intf.clk, intf.rst, intf.op, intf.din, intf.addr, intf.dout, intf.start_bit, intf.done, intf.busy, intf.ack_err, intf.sda_bus, intf.bus_val);
  
  initial begin
    intf.clk <= 1'b0;
  end
  
  always #12.5 intf.clk <= ~intf.clk;
  
  localparam raddr = 7'h11;
  
  reg [7:0] temp_addr, temp_data;
  reg [7:0] temp_store;
  
  task reset();
    intf.rst <= 1'b1;
    intf.din <= 0;
    intf.addr <= 0;
    intf.op <= 1'b0;
    temp_data <= 0;
    temp_addr <= 0;
    temp_store <= 0;
    repeat(10)@(posedge intf.clk);
    $display("[SLAVE] SYSTEM RESET");
    intf.rst <= 1'b0;
  endtask
  
  task data_capture(int state_recv, bit[8:0] count_recv, virtual i2c_intf intf, output [7:0] temp);
    begin
      wait((DUT.bridge.state == state_recv)&&(DUT.bridge.count == count_recv));
      if(intf.bus_val) begin
        $display("[SLAVE] DATA RECEIVED: %0d", intf.sda_bus[1]);
        temp[7:0] = {temp[6:0], intf.sda_bus[1]};
      end
      else begin
        $display("[SLAVE] DATA RECEIVED: %0d", intf.sda_bus[0]);
        temp[7:0] = {temp[6:0], intf.sda_bus[0]};
      end
      wait(DUT.bridge.count == `clk4*4 - 1);
    end
  endtask
  
  bit temp_value_slave;
  
  task data_send(int state_recv, bit[8:0] count_recv, virtual i2c_intf intf, output bit [7:0] temp);
    temp_value_slave = $urandom; 
    temp[7:0] = {temp[6:0], temp_value_slave};
    $display("[SLAVE] DATA SENT: %0b", temp);
    
    wait((DUT.bridge.state == state_recv)&&(DUT.bridge.count == count_recv));
    if(intf.bus_val) intf.data_1 <= temp_value_slave;
    else intf.data_0 <= temp_value_slave;
    
    wait(DUT.bridge.count == `clk4+5);
    if(intf.bus_val) begin
      $display("[SIMULATION] BUS_VAL: %0b", intf.sda_bus[1]);
    end
    else begin
      $display("[SIMULATION] BUS_VAL: %0b", intf.sda_bus[0]); 
    end
    
    wait(DUT.bridge.count == `clk4*2+5);
    $display("[BRIDGE] RECEIVED VALUE: %0b", DUT.bridge.temp_data_slave); 
    
    $display("     ");
  endtask
  
  task run(transaction trans);
    $display("----------------------");
    $display("[SLAVE] STIMULUS GEN");
    
    assert(trans.randomize()) else $error("[SLAVE] RANDOMIZATION FAILED");
    
    intf.addr <= trans.addr; //MASTER INPUT
    intf.op <= trans.op; //MASTER INPUT
    intf.din <= trans.din; //MASTER INPUT
    intf.wr_en_s0 <= 1'b0;
    intf.wr_en_s1 <= 1'b0;
    intf.data_0 <= 1'b0;
    intf.data_1 <= 1'b0;
    intf.start_bit <= 1'b1; //MASTER INPUT
    $display("din: %b, addr: %b, op: %b", trans.din, trans.addr, trans.op);
    
    $display("----------------------");
    
    $display("[SLAVE] CHECK ADDR");
    
    repeat(8) begin : CAPTURE_ADDR
      data_capture(3, 200, intf, temp_addr);
    end
    
    if(temp_addr == {intf.op, intf.addr} || temp_addr == {intf.op, raddr}) begin : CHECK_ADDR
      $display("[SLAVE] ADDRESS MATCHED");
      wait((DUT.bridge.state == 4)&&DUT.bridge.count == `clk4);
      if(intf.bus_val) begin
        intf.wr_en_s1 <= 1'b1;
        intf.data_1 <= 1'b0;
      end
      else begin
        intf.wr_en_s0 <= 1'b1;
        intf.data_0 <= 1'b0;
      end
      
      wait(DUT.bridge.count == `clk4+1);
      $display("[SLAVE] SENT NACK %0d To BRIDGE", intf.data_0);
      
      wait(DUT.bridge.count == `clk4*2 + 1);
      $display("[BRIDGE] RECEIVED NACK: %0d", DUT.bridge.recv_ack);
      
      wait(DUT.bridge.count == `clk4*4 - 1);
      if(intf.bus_val) begin
        intf.wr_en_s1 <= 1'b0;
      end
      else begin
        intf.wr_en_s0 <= 1'b0;
      end
    end
    else begin
      $display("[SLAVE] ADDRESS MISMATCH");
      $display("[SLAVE] ENDING SIMULATION");
      
      wait((DUT.bridge.state == 4)&&DUT.bridge.count == 100);
      if(intf.bus_val) begin
        intf.wr_en_s1 <= 1'b1;
        intf.data_1 <= 1'b1;
      end
      else begin
        intf.wr_en_s0 <= 1'b1;
        intf.data_0 <= 1'b1;
      end
      
      wait(DUT.bridge.count == `clk4*4 - 1);
      $display("[SLAVE] SENT NACK %0d To BRIDGE", intf.data_0);
      if(intf.bus_val) begin
        intf.wr_en_s1 <= 1'b0;
      end
      else begin
        intf.wr_en_s0 <= 1'b0;
      end
      $finish();
    end
    
    wait((DUT.master.state == 5)&&(DUT.master.count ==201));
    
    if(DUT.master.recv_ack == 1'b0) $display("[MASTER] RECEIVED NACK: 0");
    else begin
      $display("[MASTER] NACK RECEIVED 1");
      $display("[MASTER] ENDING SIMULATION");
      $finish();
    end
    
    if(temp_addr[7]) begin : OP_CHECK
      $display("[SLAVE] READ MODE\n[SLAVE] SENDING DATA...");
      read();
    end
    else begin
      $display("[SLAVE] WRITE_MODE\n[SLAVE] WAITING FOR DATA...");
      write();
    end
  endtask
  
  task read();
    $display("----------------------");
    $display("[SLAVE] DATA SENT");
    
    if(intf.bus_val) begin
      intf.wr_en_s1 <= 1'b1;
    end
    else begin
      intf.wr_en_s0 <= 1'b1;
    end
    repeat(8) begin: SEND_DATA
      data_send(10, 100, intf, temp_store);
    end
    if(intf.bus_val) begin
      intf.wr_en_s1 <= 1'b0;
    end
    else begin
      intf.wr_en_s0 <= 1'b0;
    end
    
    wait(DUT.bridge.count == `clk4*3 + 1);
    if(DUT.bridge.temp_data_slave == temp_store) begin
      $display("[BRIDGE] CORRECT DATA RECEIVED");
    end
    else begin
      $display("[BRIDGE] WRONG DATA RECEIVED");
    end

    repeat(8) begin: MASTER_CHECK_READ_DATA
      wait((DUT.master.count == `clk4*2+5)&&(DUT.master.state == 11));
      wait(DUT.master.count == 399);
    end
    
    if(DUT.master.temp_dout == temp_store) begin
      $display("[MASTER] RECEIVED CORRECT DATA");
    end
    else begin
      $display("[MASTER] RECEIVED WRONG DATA");
    end
    
    wait((DUT.bridge.state == 12)&&(DUT.bridge.count == `clk4*2 + 5)); // <-- semicolon fixed
    
    if(DUT.bridge.recv_ack == 1'b1) begin: ACK_CHECK_M2B
      $display("[BRIDGE] RECEIVED ACK: %0d FROM MASTER", DUT.bridge.recv_ack);
    end
    else begin
      $display("[BRIDGE] RECEIVED ACK: %0d FROM MASTER", DUT.bridge.recv_ack);
    end
    
    wait((DUT.bridge.state == 13)&&(DUT.bridge.count == `clk4*2+5));
    if(intf.sda_bus[0] == 1'b1) begin: ACK_CHECK_B2S
      if(intf.bus_val) begin
        $display("[SLAVE] RECEIVED ACK: %0d FROM BRIDGE", intf.sda_bus[1]);
      end
      else begin
        $display("[SLAVE] RECEIVED ACK: %0d FROM BRIDGE", intf.sda_bus[0]);
      end
    end
    else begin
      if(intf.bus_val) begin
        $display("[SLAVE] RECEIVED ACK: %0d FROM BRIDGE", intf.sda_bus[1]);
      end
      else begin
        $display("[SLAVE] RECEIVED ACK: %0d FROM BRIDGE", intf.sda_bus[0]);
      end
      $display("[SLAVE] ENDIND SIMULATION");
    end
    
    $display("[SLAVE] READ OPERATION SUCCESSFUL");
    
    $display("----------------------");
  endtask
  
  task write();
    $display("----------------------");
    $display("[SLAVE] CHECK DATA");
    
    repeat(8) begin: CAPTURE_DATA
      data_capture(7, 200, intf, temp_data);
    end
    
    if(temp_data == intf.din) begin: WRITE_DATA_CHECK
      $display("[SLAVE] WRITE DATA MATCHED");
      
      wait((DUT.bridge.state == 8)&&(DUT.bridge.count == `clk4));
      if(intf.bus_val) begin
        intf.wr_en_s1 <= 1'b1;
        intf.data_1 <= 1'b0; // <-- fixed typo (was wr_data_1)
      end
      else begin
       intf.wr_en_s0 <= 1'b1;
       intf.data_0 <= 1'b0;
      end
      
      wait(DUT.bridge.count == `clk4+1);
      $display("[SLAVE] SENT NACK 0 TO BRIDGE");
      
      wait(DUT.bridge.count == `clk4*2+1);
      
      if(DUT.bridge.recv_ack == 1'b0) begin
        $display("[BRIDGE] RECEIVED NACK: 0");
      end
      else begin
        $display("[SLAVE] RECEIVED NACK 1");
        $display("[SLAVE] ENDIND SIMULATION");
        $finish();
      end
      
      wait(DUT.bridge.count == `clk4*4 - 1);
      if(intf.bus_val) begin
        intf.wr_en_s1 <= 1'b0;
      end
      else begin
        intf.wr_en_s0 <= 1'b0;
      end
    end
    else begin
      $display("[SLAVE] WRITE DATA MISMATCHED");
      $display("[SLAVE] ENDING SIMULATION");
      
      wait((DUT.bridge.state == 8)&&(DUT.bridge.count == `clk4));
      if(intf.bus_val) begin
        intf.wr_en_s1 <= 1'b1;
        intf.data_1 <= 1'b1;
      end
      else begin
       intf.wr_en_s0 <= 1'b1;
       intf.data_0 <= 1'b1;
      end
      
      wait(DUT.bridge.count == `clk4+1);
      $display("[SLAVE] SENT NACK 1 TO BRIDGE");
      
      if(DUT.bridge.recv_ack == 1'b1) begin
        $display("[BRIDGE] RECEIVED NACK 1");
      end
      else begin
        $display("[SLAVE] RECEIVED NACK 1");
        $display("[SLAVE] ENDING SIMULATION");
        $finish();
      end
      
      wait(DUT.bridge.count == `clk4*4 - 1);
      if(intf.bus_val) begin
        intf.wr_en_s1 <= 1'b0;
      end
      else begin
        intf.wr_en_s0 <= 1'b0;
      end
      $finish();
    end
    
    wait((DUT.master.state == 9)&&(DUT.master.count ==201));
    if(DUT.master.recv_ack == 1'b0) begin
      $display("[MASTER] RECEIVED NACK: 0");
      $display("[SIMULATION] WRITE MODE IS WORKING CORRECTLY");
    end
    else begin
      $display("[MASTER] NACK RECEIVED 1");
      $display("[MASTER] ENDING SIMULATION");
      $finish();
    end
    
    $display("----------------------");
  endtask
  
  assign intf.sda_bus[0] = (intf.wr_en_s0) ? intf.data_0:1'bz;
  assign intf.sda_bus[1] = (intf.wr_en_s1) ? intf.data_1:1'bz;

  
  initial begin
    trans = new();
    trans.change = 1'b0;
    
    reset();
    $display("[SIMULATION] READ MODE");
    run(trans);
    reset();
    $display("[SIMULATION] WRITE MODE");
    trans.op_cons.constraint_mode(0);
    run(trans);
    
    // CASE FOR SAME ADDRESS SDA_BUS[1] WILL DO THE TALKING
    reset();
    trans.op_cons.constraint_mode(1);
    trans.change = 1'b1;
    $display("[SIMULATION] TWO SLAVE WITH SAME ADDR\nOUTPUT FROM MUXED WIRE");
    run(trans);
    wait(intf.done);
    $finish();
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
  
endmodule
