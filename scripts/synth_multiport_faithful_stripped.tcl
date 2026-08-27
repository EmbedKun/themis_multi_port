set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
if {[llength $argv] > 0} {
  set build_root [file normalize [lindex $argv 0]]
} elseif {[info exists ::env(HESTIA_FAITHFUL_SYNTH_ROOT)] && $::env(HESTIA_FAITHFUL_SYNTH_ROOT) ne ""} {
  set build_root [file normalize $::env(HESTIA_FAITHFUL_SYNTH_ROOT)]
} else {
  set build_root [file join $repo_dir build hestia_faithful_stripped]
}
file mkdir $build_root

set part_name "xcu200-fsgd2104-2-e"
if {[llength $argv] > 1} {
  set clk_period_ns [lindex $argv 1]
} else {
  set clk_period_ns 5.000
}

set rtl_files [list \
  [file join $repo_dir rtl hestia_pkg.sv] \
  [file join $repo_dir rtl hestia_port_bbq.sv] \
  [file join $repo_dir rtl hestia_faithful_core.sv] \
]

read_verilog -sv $rtl_files
synth_design -top hestia_faithful_core -part $part_name -mode out_of_context \
  -generic PORTS=4 \
  -generic RANK_WIDTH=8 \
  -generic SEQ_WIDTH=16 \
  -generic PAYLOAD_WIDTH=32 \
  -generic CELL_COUNT_WIDTH=4 \
  -generic SRAM_CELLS=8 \
  -generic BATCH_SIZE=4 \
  -generic BATCH_SLOTS=8 \
  -generic PACKET_SLOTS=32
create_clock -period $clk_period_ns -name clk [get_ports clk]

report_utilization -file [file join $build_root faithful_utilization_synth.rpt]
report_utilization -hierarchical -file [file join $build_root faithful_utilization_hier_synth.rpt]
report_timing_summary -max_paths 10 -file [file join $build_root faithful_timing_summary_synth.rpt]

puts "Hestia faithful stripped utilization: [file join $build_root faithful_utilization_synth.rpt]"
puts "Hestia faithful stripped hierarchical utilization: [file join $build_root faithful_utilization_hier_synth.rpt]"
puts "Hestia faithful stripped timing summary: [file join $build_root faithful_timing_summary_synth.rpt]"
exit 0
