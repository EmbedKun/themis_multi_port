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

proc hestia_pct {num den} {
  if {$den == 0} {
    return "0.0%"
  }
  return [format "%.1f%%" [expr {100.0 * $num / $den}]]
}

proc hestia_write_paper_resource_report {build_root ports clk_period_ns util_report timing_report} {
  set themis_lut [hestia_env_or HESTIA_RESOURCE_THEMIS_LUT 7157]
  set themis_ff [hestia_env_or HESTIA_RESOURCE_THEMIS_FF 7435]

  if {$ports <= 1} {
    set overlay_lut 0
    set overlay_ff 0
  } else {
    set overlay_lut [expr {240 + 403 * $ports}]
    set overlay_ff [expr {480 + 335 * $ports}]
  }
  set overlay_lut [hestia_env_or HESTIA_RESOURCE_OVERLAY_LUT $overlay_lut]
  set overlay_ff [hestia_env_or HESTIA_RESOURCE_OVERLAY_FF $overlay_ff]

  set themis_n_lut [expr {$themis_lut * $ports}]
  set themis_n_ff [expr {$themis_ff * $ports}]
  set hestia_norm_lut [expr {$themis_n_lut + $overlay_lut}]
  set hestia_norm_ff [expr {$themis_n_ff + $overlay_ff}]

  set raw_lut [hestia_parse_util_metric $util_report "CLB LUTs"]
  set raw_ff [hestia_parse_util_metric $util_report "CLB Registers"]
  set raw_lutram [hestia_parse_util_metric $util_report "LUT as Memory"]
  set raw_bram [hestia_parse_util_metric $util_report "Block RAM Tile"]
  set raw_uram [hestia_parse_util_metric $util_report "URAM"]
  set raw_dsp [hestia_parse_util_metric $util_report "DSPs"]
  set wns [hestia_parse_wns $timing_report]

  set md_path [file join $build_root hestia_paper_resource_table.md]
  set csv_path [file join $build_root hestia_paper_resource_table.csv]

  set md [open $md_path w]
  puts $md "# Hestia Paper-Style Resource Accounting"
  puts $md ""
  puts $md "Ports: $ports"
  puts $md [format "Clock target: %.3f ns (%.1f MHz)" $clk_period_ns [expr {1000.0 / $clk_period_ns}]]
  puts $md ""
  puts $md "| Row | CLB LUTs | CLB Registers | Extra LUTs | Extra FFs | Notes |"
  puts $md "| --- | ---: | ---: | ---: | ---: | --- |"
  puts $md "| Themis paper 1P | $themis_lut | $themis_ff | 0 | 0 | single-port Themis FPGA core from the paper table |"
  puts $md "| ${ports}x Themis paper cores | $themis_n_lut | $themis_n_ff | 0 | 0 | linear per-port baseline |"
  puts $md "| Hestia-${ports}P paper-projection | $hestia_norm_lut | $hestia_norm_ff | $overlay_lut ([hestia_pct $overlay_lut $themis_n_lut]) | $overlay_ff ([hestia_pct $overlay_ff $themis_n_ff]) | model: per-port Themis-equivalent control plus shared BM overlay |"
  if {$raw_lut >= 0 && $raw_ff >= 0} {
    set timing_note "timing report not provided"
    if {$wns ne ""} {
      set timing_note "WNS [format "%+.3f" $wns] ns"
    }
    puts $md "| Hestia-${ports}P raw RTL resource-core | $raw_lut | $raw_ff | [expr {$raw_lut - $themis_n_lut}] | [expr {$raw_ff - $themis_n_ff}] | Vivado OOC descriptor core, excludes generator/ILA/stat outputs, $timing_note |"
  }
  puts $md ""
  puts $md "Raw implementation details: LUTRAM=$raw_lutram, BRAM tiles=$raw_bram, URAM=$raw_uram, DSP=$raw_dsp."
  puts $md ""
  puts $md "The paper-projection row is an accounting model. The raw RTL row is the Vivado-measured descriptor core and is kept for reproducibility. Neither row should be mixed with a full U200 design that includes DDR4 IP, ILA cores, synthetic traffic generation, and checkers."
  puts $md ""
  puts $md "```text"
  puts $md "Hestia_NP_LUT = N * Themis_1P_LUT + shared_lut(N)"
  puts $md "Hestia_NP_FF  = N * Themis_1P_FF  + shared_ff(N)"
  puts $md "shared_lut(N) = 240 + 403 * N, for N >= 2"
  puts $md "shared_ff(N)  = 480 + 335 * N, for N >= 2"
  puts $md "```"
  close $md

  set csv [open $csv_path w]
  puts $csv "row,ports,clb_luts,clb_registers,extra_luts,extra_ffs,wns_ns,notes"
  puts $csv "themis_paper_1p,1,$themis_lut,$themis_ff,0,0,,single-port Themis paper FPGA core"
  puts $csv "${ports}x_themis_paper,$ports,$themis_n_lut,$themis_n_ff,0,0,,linear per-port baseline"
  puts $csv "hestia_${ports}p_paper_projection,$ports,$hestia_norm_lut,$hestia_norm_ff,$overlay_lut,$overlay_ff,,model: Themis-equivalent per-port cost plus shared BM overlay"
  if {$raw_lut >= 0 && $raw_ff >= 0} {
    puts $csv "hestia_${ports}p_raw_rtl_resource_core,$ports,$raw_lut,$raw_ff,[expr {$raw_lut - $themis_n_lut}],[expr {$raw_ff - $themis_n_ff}],$wns,Vivado OOC descriptor core"
  }
  close $csv

  puts "Hestia paper resource table: $md_path"
  puts "Hestia paper resource CSV: $csv_path"
  puts "Hestia-${ports}P paper-projection: LUT=$hestia_norm_lut FF=$hestia_norm_ff overlay_lut=$overlay_lut overlay_ff=$overlay_ff"
  if {$raw_lut >= 0 && $raw_ff >= 0} {
    puts "Hestia-${ports}P raw resource-core: LUT=$raw_lut FF=$raw_ff LUTRAM=$raw_lutram BRAM=$raw_bram URAM=$raw_uram DSP=$raw_dsp WNS=$wns"
  }
}

set ports [hestia_env_or HESTIA_RESOURCE_PORTS 2]
set build_root_default [file join $repo_dir build hestia_resource_core_${ports}p]
if {[llength $argv] > 0} {
  set build_root [file normalize [lindex $argv 0]]
} elseif {[info exists ::env(HESTIA_RESOURCE_SYNTH_ROOT)] && $::env(HESTIA_RESOURCE_SYNTH_ROOT) ne ""} {
  set build_root [file normalize $::env(HESTIA_RESOURCE_SYNTH_ROOT)]
} else {
  set build_root $build_root_default
}
file mkdir $build_root

set part_name [hestia_env_or HESTIA_RESOURCE_PART xcu200-fsgd2104-2-e]
if {[llength $argv] > 1} {
  set clk_period_ns [lindex $argv 1]
} else {
  set clk_period_ns [hestia_env_or HESTIA_RESOURCE_CLK_PERIOD_NS 3.333]
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
set external_metadata [hestia_env_or HESTIA_RESOURCE_EXTERNAL_METADATA 0]

set sram_cells [hestia_env_or HESTIA_RESOURCE_SRAM_CELLS [expr {$per_port_sram_cells * $ports}]]
set batch_slots [hestia_env_or HESTIA_RESOURCE_BATCH_SLOTS [expr {$per_port_batches * $ports}]]
set packet_slots [hestia_env_or HESTIA_RESOURCE_PACKET_SLOTS [expr {$per_port_packets * $ports}]]

puts "Hestia resource-core synthesis configuration:"
puts "  ports=${ports} period=${clk_period_ns}ns part=${part_name}"
puts "  rank_width=${rank_width} seq_width=${seq_width} payload_width=${payload_width}"
puts "  sram_cells=${sram_cells} batch_size=${batch_size} batch_slots=${batch_slots} packet_slots=${packet_slots}"
puts "  bbq_bitmap_width=${bbq_bitmap_width}"
puts "  external_metadata=${external_metadata}"

set rtl_files [list \
  [file join $repo_dir rtl hestia_pkg.sv] \
  [file join $repo_dir rtl hestia_port_bbq.sv] \
  [file join $repo_dir rtl hestia_policy_dt.sv] \
  [file join $repo_dir rtl hestia_policy_occamy.sv] \
  [file join $repo_dir rtl hestia_policy_obm.sv] \
  [file join $repo_dir rtl hestia_policy_hybrid_themis.sv] \
  [file join $repo_dir rtl hestia_paper_scale_resource_core.sv] \
  [file join $repo_dir rtl hestia_core_ddr_bbq_extmeta.sv] \
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
  -generic EXTERNAL_METADATA=$external_metadata \
  -generic ENABLE_DDR_META_CHECK=0
create_clock -period $clk_period_ns -name clk [get_ports clk]

report_utilization -file [file join $build_root resource_core_utilization_synth.rpt]
report_utilization -hierarchical -file [file join $build_root resource_core_utilization_hier_synth.rpt]
report_timing_summary -max_paths 10 -file [file join $build_root resource_core_timing_summary_synth.rpt]

puts "Hestia resource-core utilization: [file join $build_root resource_core_utilization_synth.rpt]"
puts "Hestia resource-core hierarchical utilization: [file join $build_root resource_core_utilization_hier_synth.rpt]"
puts "Hestia resource-core timing summary: [file join $build_root resource_core_timing_summary_synth.rpt]"
hestia_write_paper_resource_report $build_root $ports $clk_period_ns \
  [file join $build_root resource_core_utilization_synth.rpt] \
  [file join $build_root resource_core_timing_summary_synth.rpt]
exit 0
