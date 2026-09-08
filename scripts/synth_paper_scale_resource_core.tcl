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
    -1 { return "hestia" }
    0 { return "dt_hybrid" }
    1 { return "occamy_hybrid" }
    3 { return "obm_hybrid" }
    default { return "policy_${policy}" }
  }
}

set policy_mode [hestia_env_or HESTIA_PAPER_POLICY_MODE -1]
set policy_name [hestia_policy_name $policy_mode]
set ports [hestia_env_or HESTIA_PAPER_PORTS 4]
set part_name [hestia_env_or HESTIA_PAPER_PART xcu200-fsgd2104-2-e]
set clk_period_ns [hestia_env_or HESTIA_PAPER_CLK_PERIOD_NS 3.333]

if {[llength $argv] > 0} {
  set build_root [file normalize [lindex $argv 0]]
} elseif {[info exists ::env(HESTIA_PAPER_SYNTH_ROOT)] && $::env(HESTIA_PAPER_SYNTH_ROOT) ne ""} {
  set build_root [file normalize $::env(HESTIA_PAPER_SYNTH_ROOT)]
} else {
  set build_root [file join $repo_dir build paper_scale_${policy_name}_${ports}p]
}
if {[llength $argv] > 1} {
  set clk_period_ns [lindex $argv 1]
}
file mkdir $build_root

set rank_width [hestia_env_or HESTIA_PAPER_RANK_WIDTH 10]
set seq_width [hestia_env_or HESTIA_PAPER_SEQ_WIDTH 16]
set cell_count_width [hestia_env_or HESTIA_PAPER_CELL_COUNT_WIDTH 16]
set cell_bytes [hestia_env_or HESTIA_PAPER_CELL_BYTES 64]
set sram_bytes [hestia_env_or HESTIA_PAPER_SRAM_BYTES 5242880]
set ddr_bytes_log2 [hestia_env_or HESTIA_PAPER_DDR_BYTES_LOG2 32]
set batch_size [hestia_env_or HESTIA_PAPER_BATCH_SIZE 8]
set bbq_bitmap_width [hestia_env_or HESTIA_PAPER_BBQ_BITMAP_WIDTH 32]
set alpha_shift [hestia_env_or HESTIA_PAPER_ALPHA_SHIFT 0]

set sram_cells [expr {$sram_bytes / $cell_bytes}]
set ddr_cells [expr {1 << ($ddr_bytes_log2 - int(log($cell_bytes) / log(2)))}]
set batch_slots [expr {$ddr_cells / $batch_size}]

puts "Hestia paper-scale core-only synthesis:"
puts "  policy=${policy_mode} (${policy_name}) ports=${ports} part=${part_name} period=${clk_period_ns}ns"
puts "  SRAM=${sram_bytes} bytes (${sram_cells} cells) DDR=2^${ddr_bytes_log2} bytes (${ddr_cells} cells)"
puts "  rank_width=${rank_width} seq_width=${seq_width} cell_count_width=${cell_count_width}"
puts "  batch_size=${batch_size} batch_slots=${batch_slots} bbq_bitmap_width=${bbq_bitmap_width}"
puts "  excludes payload SRAM arrays, DDR IP, ILA, generators, checkers, and debug counters"

set rtl_files [list \
  [file join $repo_dir rtl hestia_policy_dt.sv] \
  [file join $repo_dir rtl hestia_policy_occamy.sv] \
  [file join $repo_dir rtl hestia_policy_obm.sv] \
  [file join $repo_dir rtl hestia_paper_scale_resource_core.sv] \
]

read_verilog -sv $rtl_files
synth_design -top hestia_paper_scale_resource_core -part $part_name -mode out_of_context \
  -generic PORTS=$ports \
  -generic POLICY_MODE=$policy_mode \
  -generic RANK_WIDTH=$rank_width \
  -generic SEQ_WIDTH=$seq_width \
  -generic CELL_COUNT_WIDTH=$cell_count_width \
  -generic CELL_BYTES=$cell_bytes \
  -generic SRAM_BYTES=$sram_bytes \
  -generic DDR_BYTES_LOG2=$ddr_bytes_log2 \
  -generic BATCH_SIZE=$batch_size \
  -generic BBQ_BITMAP_WIDTH=$bbq_bitmap_width
create_clock -period $clk_period_ns -name clk [get_ports clk]

set util_report [file join $build_root paper_scale_utilization_synth.rpt]
set hier_report [file join $build_root paper_scale_utilization_hier_synth.rpt]
set timing_report [file join $build_root paper_scale_timing_summary_synth.rpt]
report_utilization -file $util_report
report_utilization -hierarchical -file $hier_report
report_timing_summary -max_paths 10 -file $timing_report

set lut [hestia_parse_util_metric $util_report "CLB LUTs"]
set ff [hestia_parse_util_metric $util_report "CLB Registers"]
set lutram [hestia_parse_util_metric $util_report "LUT as Memory"]
set bram [hestia_parse_util_metric $util_report "Block RAM Tile"]
set uram [hestia_parse_util_metric $util_report "URAM"]
set dsp [hestia_parse_util_metric $util_report "DSPs"]
set wns [hestia_parse_wns $timing_report]

set csv_path [file join $build_root paper_scale_resource.csv]
set csv [open $csv_path w]
puts $csv "design,policy_mode,ports,sram_bytes,sram_cells,ddr_bytes_log2,ddr_cells,batch_size,batch_slots,rank_width,seq_width,cell_count_width,bbq_bitmap_width,clb_luts,clb_registers,lutram,bram_tiles,uram,dsps,wns_ns"
puts $csv "$policy_name,$policy_mode,$ports,$sram_bytes,$sram_cells,$ddr_bytes_log2,$ddr_cells,$batch_size,$batch_slots,$rank_width,$seq_width,$cell_count_width,$bbq_bitmap_width,$lut,$ff,$lutram,$bram,$uram,$dsp,$wns"
close $csv

puts "paper_scale_utilization: $util_report"
puts "paper_scale_hierarchical_utilization: $hier_report"
puts "paper_scale_timing_summary: $timing_report"
puts "paper_scale_csv: $csv_path"
puts "RESULT policy=${policy_mode} name=${policy_name} ports=${ports} LUT=${lut} FF=${ff} LUTRAM=${lutram} BRAM=${bram} URAM=${uram} DSP=${dsp} WNS=${wns}"
exit 0
