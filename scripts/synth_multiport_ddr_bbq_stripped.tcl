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

proc hestia_env_or {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

set part_name "xcu200-fsgd2104-2-e"
if {[llength $argv] > 1} {
  set clk_period_ns [lindex $argv 1]
} else {
  set clk_period_ns 8.000
}

set synth_ports [hestia_env_or HESTIA_SYNTH_PORTS 4]
set synth_rank_width [hestia_env_or HESTIA_SYNTH_RANK_WIDTH 6]
set synth_seq_width [hestia_env_or HESTIA_SYNTH_SEQ_WIDTH 16]
set synth_payload_width [hestia_env_or HESTIA_SYNTH_PAYLOAD_WIDTH 32]
set synth_cell_count_width [hestia_env_or HESTIA_SYNTH_CELL_COUNT_WIDTH 4]
set synth_sram_cells [hestia_env_or HESTIA_SYNTH_SRAM_CELLS 16]
set synth_batch_size [hestia_env_or HESTIA_SYNTH_BATCH_SIZE 8]
set synth_batch_slots [hestia_env_or HESTIA_SYNTH_BATCH_SLOTS 32]
set synth_packet_slots [hestia_env_or HESTIA_SYNTH_PACKET_SLOTS 64]
set synth_bbq_bitmap_width [hestia_env_or HESTIA_SYNTH_BBQ_BITMAP_WIDTH 8]

set rtl_files [list \
  [file join $repo_dir rtl hestia_pkg.sv] \
  [file join $repo_dir rtl hestia_port_bbq.sv] \
  [file join $repo_dir rtl hestia_policy_dt.sv] \
  [file join $repo_dir rtl hestia_policy_occamy.sv] \
  [file join $repo_dir rtl hestia_policy_obm.sv] \
  [file join $repo_dir rtl hestia_core_ddr_bbq.sv] \
]

read_verilog -sv $rtl_files
synth_design -top hestia_core_ddr_bbq -part $part_name -mode out_of_context \
  -generic PORTS=$synth_ports \
  -generic RANK_WIDTH=$synth_rank_width \
  -generic SEQ_WIDTH=$synth_seq_width \
  -generic PAYLOAD_WIDTH=$synth_payload_width \
  -generic CELL_COUNT_WIDTH=$synth_cell_count_width \
  -generic SRAM_CELLS=$synth_sram_cells \
  -generic BATCH_SIZE=$synth_batch_size \
  -generic BATCH_SLOTS=$synth_batch_slots \
  -generic PACKET_SLOTS=$synth_packet_slots \
  -generic BBQ_BITMAP_WIDTH=$synth_bbq_bitmap_width
create_clock -period $clk_period_ns -name clk [get_ports clk]

report_utilization -file [file join $build_root ddr_bbq_utilization_synth.rpt]
report_utilization -hierarchical -file [file join $build_root ddr_bbq_utilization_hier_synth.rpt]
report_timing_summary -max_paths 10 -file [file join $build_root ddr_bbq_timing_summary_synth.rpt]

puts "Hestia DDR BBQ stripped utilization: [file join $build_root ddr_bbq_utilization_synth.rpt]"
puts "Hestia DDR BBQ stripped hierarchical utilization: [file join $build_root ddr_bbq_utilization_hier_synth.rpt]"
puts "Hestia DDR BBQ stripped timing summary: [file join $build_root ddr_bbq_timing_summary_synth.rpt]"
exit 0
