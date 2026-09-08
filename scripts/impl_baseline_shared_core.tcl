set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]

proc hestia_env_or {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

proc hestia_parse_util_metric {report_path label} {
  if {![file exists $report_path]} {
    return -1
  }
  set fh [open $report_path r]
  set value -1
  set pattern "\\|\\s*$label\\*?\\s*\\|\\s*([0-9.]+)\\s*\\|"
  while {[gets $fh line] >= 0} {
    if {[regexp $pattern $line -> raw_value]} {
      set value [expr {int(double($raw_value))}]
      break
    }
  }
  close $fh
  return $value
}

proc hestia_parse_wns {report_path} {
  if {![file exists $report_path]} {
    return ""
  }
  set fh [open $report_path r]
  set in_summary 0
  set value ""
  while {[gets $fh line] >= 0} {
    if {[string first "Design Timing Summary" $line] >= 0} {
      set in_summary 1
      continue
    }
    if {$in_summary && [regexp {^\s*([-+]?[0-9]+\.[0-9]+)\s+[-+]?[0-9]+\.[0-9]+\s+\d+} $line -> raw_value]} {
      set value $raw_value
      break
    }
  }
  close $fh
  return $value
}

proc hestia_policy_name {policy} {
  switch -- $policy {
    0 { return "dt" }
    1 { return "occamy_head" }
    2 { return "occamy_max" }
    3 { return "obm" }
    default { return "unknown" }
  }
}

set policy_mode [hestia_env_or HESTIA_BASELINE_POLICY_MODE 0]
set policy_name [hestia_policy_name $policy_mode]
set part_name [hestia_env_or HESTIA_BASELINE_PART xcu200-fsgd2104-2-e]
set clk_period_ns [hestia_env_or HESTIA_BASELINE_CLK_PERIOD_NS 5.000]

if {[llength $argv] > 0} {
  set build_root [file normalize [lindex $argv 0]]
} elseif {[info exists ::env(HESTIA_BASELINE_IMPL_ROOT)] && $::env(HESTIA_BASELINE_IMPL_ROOT) ne ""} {
  set build_root [file normalize $::env(HESTIA_BASELINE_IMPL_ROOT)]
} else {
  set build_root [file join $repo_dir build hestia_baseline_${policy_name}_4p_impl]
}
if {[llength $argv] > 1} {
  set clk_period_ns [lindex $argv 1]
}
file mkdir $build_root

set synth_ports [hestia_env_or HESTIA_BASELINE_PORTS 4]
set synth_rank_width [hestia_env_or HESTIA_BASELINE_RANK_WIDTH 6]
set synth_seq_width [hestia_env_or HESTIA_BASELINE_SEQ_WIDTH 16]
set synth_payload_width [hestia_env_or HESTIA_BASELINE_PAYLOAD_WIDTH 32]
set synth_cell_count_width [hestia_env_or HESTIA_BASELINE_CELL_COUNT_WIDTH 4]
set synth_sram_cells [hestia_env_or HESTIA_BASELINE_SRAM_CELLS 32]
set synth_packet_slots [hestia_env_or HESTIA_BASELINE_PACKET_SLOTS 64]
set synth_bbq_bitmap_width [hestia_env_or HESTIA_BASELINE_BBQ_BITMAP_WIDTH 8]
set synth_alpha_shift_width [hestia_env_or HESTIA_BASELINE_ALPHA_SHIFT_WIDTH 4]

set rtl_files [list \
  [file join $repo_dir rtl hestia_pkg.sv] \
  [file join $repo_dir rtl hestia_port_bbq.sv] \
  [file join $repo_dir rtl hestia_policy_dt.sv] \
  [file join $repo_dir rtl hestia_policy_occamy.sv] \
  [file join $repo_dir rtl hestia_policy_obm.sv] \
  [file join $repo_dir rtl hestia_baseline_shared_core.sv] \
]

read_verilog -sv $rtl_files
synth_design -top hestia_baseline_shared_core -part $part_name -mode out_of_context \
  -generic POLICY_MODE=$policy_mode \
  -generic PORTS=$synth_ports \
  -generic RANK_WIDTH=$synth_rank_width \
  -generic SEQ_WIDTH=$synth_seq_width \
  -generic PAYLOAD_WIDTH=$synth_payload_width \
  -generic CELL_COUNT_WIDTH=$synth_cell_count_width \
  -generic SRAM_CELLS=$synth_sram_cells \
  -generic PACKET_SLOTS=$synth_packet_slots \
  -generic BBQ_BITMAP_WIDTH=$synth_bbq_bitmap_width \
  -generic ALPHA_SHIFT_WIDTH=$synth_alpha_shift_width

create_clock -period $clk_period_ns -name clk [get_ports clk]
opt_design
place_design
phys_opt_design
route_design

set util_report [file join $build_root baseline_shared_utilization_impl.rpt]
set hier_report [file join $build_root baseline_shared_utilization_hier_impl.rpt]
set timing_report [file join $build_root baseline_shared_timing_summary_impl.rpt]
set route_status_report [file join $build_root baseline_shared_route_status.rpt]
set dcp_path [file join $build_root baseline_shared_impl.dcp]

report_utilization -file $util_report
report_utilization -hierarchical -file $hier_report
report_timing_summary -max_paths 10 -file $timing_report
report_route_status -file $route_status_report
write_checkpoint -force $dcp_path

set lut [hestia_parse_util_metric $util_report "CLB LUTs"]
set ff [hestia_parse_util_metric $util_report "CLB Registers"]
set lutram [hestia_parse_util_metric $util_report "LUT as Memory"]
set bram [hestia_parse_util_metric $util_report "Block RAM Tile"]
set uram [hestia_parse_util_metric $util_report "URAM"]
set dsp [hestia_parse_util_metric $util_report "DSPs"]
set wns [hestia_parse_wns $timing_report]

set md_path [file join $build_root baseline_shared_resource_impl.md]
set md [open $md_path w]
puts $md "# Hestia Baseline Shared-Core Implementation Resource"
puts $md ""
puts $md "| Field | Value |"
puts $md "| --- | ---: |"
puts $md "| policy_mode | $policy_mode |"
puts $md "| policy_name | $policy_name |"
puts $md "| ports | $synth_ports |"
puts $md "| rank_width | $synth_rank_width |"
puts $md "| sram_cells | $synth_sram_cells |"
puts $md "| packet_slots | $synth_packet_slots |"
puts $md "| bbq_bitmap_width | $synth_bbq_bitmap_width |"
puts $md "| target_period_ns | $clk_period_ns |"
puts $md "| CLB LUTs | $lut |"
puts $md "| CLB Registers | $ff |"
puts $md "| LUTRAM | $lutram |"
puts $md "| BRAM tiles | $bram |"
puts $md "| URAM | $uram |"
puts $md "| DSP | $dsp |"
puts $md "| post_route_WNS_ns | $wns |"
close $md

set csv_path [file join $build_root baseline_shared_resource_impl.csv]
set csv [open $csv_path w]
puts $csv "policy_mode,policy_name,ports,rank_width,sram_cells,packet_slots,bbq_bitmap_width,target_period_ns,clb_luts,clb_registers,lutram,bram_tiles,uram,dsps,post_route_wns_ns"
puts $csv "$policy_mode,$policy_name,$synth_ports,$synth_rank_width,$synth_sram_cells,$synth_packet_slots,$synth_bbq_bitmap_width,$clk_period_ns,$lut,$ff,$lutram,$bram,$uram,$dsp,$wns"
close $csv

puts "Hestia baseline policy=$policy_mode ($policy_name) implemented core: LUT=$lut FF=$ff LUTRAM=$lutram BRAM=$bram URAM=$uram DSP=$dsp post_route_WNS=$wns target_period_ns=$clk_period_ns"
exit 0
