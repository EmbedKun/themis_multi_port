create_clock -name clk -period 5.000 [get_ports clk]

set_input_delay 0.30 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 0.30 -clock clk [all_outputs]
set_false_path -from [get_ports resetn]
