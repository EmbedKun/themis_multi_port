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

set ports [hestia_env_or HESTIA_RESOURCE_PORTS 4]
set build_root_default [file join $repo_dir build hestia_resource_core_${ports}p_impl]
if {[llength $argv] > 0} {
  set build_root [file normalize [lindex $argv 0]]
} elseif {[info exists ::env(HESTIA_RESOURCE_IMPL_ROOT)] && $::env(HESTIA_RESOURCE_IMPL_ROOT) ne ""} {
  set build_root [file normalize $::env(HESTIA_RESOURCE_IMPL_ROOT)]
} else {
  set build_root $build_root_default
}
file mkdir $build_root

set part_name [hestia_env_or HESTIA_RESOURCE_PART xcu200-fsgd2104-2-e]
if {[llength $argv] > 1} {
  set clk_period_ns [lindex $argv 1]
} else {
  set clk_period_ns [hestia_env_or HESTIA_RESOURCE_CLK_PERIOD_NS 5.000]
}

set per_port_packets [hestia_env_or HESTIA_RESOURCE_PACKETS_PER_PORT 16]
set per_port_sram_cells [hestia_env_or HESTIA_RESOURCE_SRAM_CELLS_PER_PORT 8]
set per_port_batches [hestia_env_or HESTIA_RESOURCE_BATCH_SLOTS_PER_PORT 8]

set rank_width [hestia_env_or HESTIA_RESOURCE_RANK_WIDTH 6]
set seq_width [hestia_env_or HESTIA_RESOURCE_SEQ_WIDTH 16]
set payload_width [hestia_env_or HESTIA_RESOURCE_PAYLOAD_WIDTH 32]
set cell_count_width [hestia_env_or HESTIA_RESOURCE_CELL_COUNT_WIDTH 4]
set batch_size [hestia_env_or HESTIA_RESOURCE_BATCH_SIZE 8]
set bbq_bitmap_width [hestia_env_or HESTIA_RESOURCE_BBQ_BITMAP_WIDTH 8]
set policy_mode [hestia_env_or HESTIA_RESOURCE_POLICY_MODE -1]
set policy_alpha_shift [hestia_env_or HESTIA_RESOURCE_POLICY_ALPHA_SHIFT 0]

set sram_cells [hestia_env_or HESTIA_RESOURCE_SRAM_CELLS [expr {$per_port_sram_cells * $ports}]]
set batch_slots [hestia_env_or HESTIA_RESOURCE_BATCH_SLOTS [expr {$per_port_batches * $ports}]]
set packet_slots [hestia_env_or HESTIA_RESOURCE_PACKET_SLOTS [expr {$per_port_packets * $ports}]]

puts "Hestia resource-core implementation configuration:"
puts "  ports=${ports} period=${clk_period_ns}ns part=${part_name}"
puts "  rank_width=${rank_width} seq_width=${seq_width} payload_width=${payload_width}"
puts "  sram_cells=${sram_cells} batch_size=${batch_size} batch_slots=${batch_slots} packet_slots=${packet_slots}"
puts "  bbq_bitmap_width=${bbq_bitmap_width}"

set rtl_files [list \
  [file join $repo_dir rtl hestia_pkg.sv] \
  [file join $repo_dir rtl hestia_port_bbq.sv] \
  [file join $repo_dir rtl hestia_policy_dt.sv] \
  [file join $repo_dir rtl hestia_policy_occamy.sv] \
  [file join $repo_dir rtl hestia_policy_obm.sv] \
  [file join $repo_dir rtl hestia_core_ddr_bbq.sv] \
  [file join $repo_dir rtl hestia_resource_core.sv] \
]

read_verilog -sv $rtl_files
synth_design -top hestia_resource_core -part $part_name -mode out_of_context \
  -generic PORTS=$ports \
  -generic RANK_WIDTH=$rank_width \
  -generic SEQ_WIDTH=$seq_width \
  -generic PAYLOAD_WIDTH=$payload_width \
  -generic CELL_COUNT_WIDTH=$cell_count_width \
  -generic SRAM_CELLS=$sram_cells \
  -generic BATCH_SIZE=$batch_size \
  -generic BATCH_SLOTS=$batch_slots \
  -generic PACKET_SLOTS=$packet_slots \
  -generic BBQ_BITMAP_WIDTH=$bbq_bitmap_width \
  -generic POLICY_MODE=$policy_mode \
  -generic POLICY_ALPHA_SHIFT=$policy_alpha_shift \
  -generic ENABLE_DDR_META_CHECK=0

create_clock -period $clk_period_ns -name clk [get_ports clk]
opt_design
place_design
phys_opt_design
route_design

set util_report [file join $build_root resource_core_utilization_impl.rpt]
set hier_report [file join $build_root resource_core_utilization_hier_impl.rpt]
set timing_report [file join $build_root resource_core_timing_summary_impl.rpt]
set route_status_report [file join $build_root resource_core_route_status.rpt]
set dcp_path [file join $build_root resource_core_impl.dcp]

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

set csv_path [file join $build_root resource_core_impl.csv]
set csv [open $csv_path w]
puts $csv "ports,rank_width,sram_cells,batch_size,batch_slots,packet_slots,bbq_bitmap_width,target_period_ns,clb_luts,clb_registers,lutram,bram_tiles,uram,dsps,post_route_wns_ns"
puts $csv "$ports,$rank_width,$sram_cells,$batch_size,$batch_slots,$packet_slots,$bbq_bitmap_width,$clk_period_ns,$lut,$ff,$lutram,$bram,$uram,$dsp,$wns"
close $csv

puts "Hestia resource-core implemented: LUT=$lut FF=$ff LUTRAM=$lutram BRAM=$bram URAM=$uram DSP=$dsp post_route_WNS=$wns target_period_ns=$clk_period_ns"
puts "Hestia resource-core reports: $util_report $timing_report $route_status_report"
exit 0
