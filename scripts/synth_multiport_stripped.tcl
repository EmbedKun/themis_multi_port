set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
if {[llength $argv] > 0} {
  set build_root [file normalize [lindex $argv 0]]
} elseif {[info exists ::env(HESTIA_SYNTH_ROOT)] && $::env(HESTIA_SYNTH_ROOT) ne ""} {
  set build_root [file normalize $::env(HESTIA_SYNTH_ROOT)]
} else {
  set build_root [file join $repo_dir build hestia_stripped]
}
file mkdir $build_root

set part_name "xcu200-fsgd2104-2-e"
if {[llength $argv] > 1} {
  set clk_period_ns [lindex $argv 1]
} else {
  set clk_period_ns 3.333
}
set rtl_files [list \
  [file join $repo_dir rtl hestia_pkg.sv] \
  [file join $repo_dir rtl hestia_port_rank_queue.sv] \
  [file join $repo_dir rtl hestia_core.sv] \
]

read_verilog -sv $rtl_files
synth_design -top hestia_core -part $part_name -mode out_of_context
create_clock -period $clk_period_ns -name clk [get_ports clk]

report_utilization -file [file join $build_root multiport_utilization_synth.rpt]
report_utilization -hierarchical -file [file join $build_root multiport_utilization_hier_synth.rpt]
report_timing_summary -max_paths 10 -file [file join $build_root multiport_timing_summary_synth.rpt]

puts "Hestia stripped utilization: [file join $build_root multiport_utilization_synth.rpt]"
puts "Hestia stripped hierarchical utilization: [file join $build_root multiport_utilization_hier_synth.rpt]"
puts "Hestia stripped timing summary: [file join $build_root multiport_timing_summary_synth.rpt]"
exit 0
