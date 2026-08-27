set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
if {[llength $argv] > 0} {
  set build_root [file normalize [lindex $argv 0]]
} elseif {[info exists ::env(HESTIA_DDR_BBQ_SYNTH_ROOT)] && $::env(HESTIA_DDR_BBQ_SYNTH_ROOT) ne ""} {
  set build_root [file normalize $::env(HESTIA_DDR_BBQ_SYNTH_ROOT)]
} else {
  set build_root [file join $repo_dir build hestia_ddr_bbq_stripped]
}
file mkdir $build_root

set part_name "xcu200-fsgd2104-2-e"
if {[llength $argv] > 1} {
  set clk_period_ns [lindex $argv 1]
} else {
  set clk_period_ns 8.000
}

set rtl_files [list \
  [file join $repo_dir rtl hestia_pkg.sv] \
  [file join $repo_dir rtl hestia_port_bbq.sv] \
  [file join $repo_dir rtl hestia_core_ddr_bbq.sv] \
]

read_verilog -sv $rtl_files
synth_design -top hestia_core_ddr_bbq -part $part_name -mode out_of_context \
  -generic PORTS=4 \
  -generic RANK_WIDTH=6 \
  -generic SEQ_WIDTH=16 \
  -generic PAYLOAD_WIDTH=32 \
  -generic CELL_COUNT_WIDTH=4 \
  -generic SRAM_CELLS=16 \
  -generic BATCH_SIZE=8 \
  -generic BATCH_SLOTS=32 \
  -generic PACKET_SLOTS=64 \
  -generic BBQ_BITMAP_WIDTH=8
create_clock -period $clk_period_ns -name clk [get_ports clk]

report_utilization -file [file join $build_root ddr_bbq_utilization_synth.rpt]
report_utilization -hierarchical -file [file join $build_root ddr_bbq_utilization_hier_synth.rpt]
report_timing_summary -max_paths 10 -file [file join $build_root ddr_bbq_timing_summary_synth.rpt]

puts "Hestia DDR BBQ stripped utilization: [file join $build_root ddr_bbq_utilization_synth.rpt]"
puts "Hestia DDR BBQ stripped hierarchical utilization: [file join $build_root ddr_bbq_utilization_hier_synth.rpt]"
puts "Hestia DDR BBQ stripped timing summary: [file join $build_root ddr_bbq_timing_summary_synth.rpt]"
exit 0
