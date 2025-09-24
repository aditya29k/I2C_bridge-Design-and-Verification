setup_fpga -tech VIRTEX7 -part xc7v585t

hlib create ./work
hlib map work ./work

hcom -lib work -verilog -sv design.sv

setoption output_edif "bjack.synth.edf"
setoption output_verilog "bjack.synth.vm"
setoption output_schematicsvg "diag.svg"

'work' library
hsyn -L work top
