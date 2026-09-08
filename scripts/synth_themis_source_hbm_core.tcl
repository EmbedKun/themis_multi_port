set script_dir [file dirname [file normalize [info script]]]

proc env_or {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

proc parse_util_metric {report_path label} {
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

proc parse_wns {report_path} {
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

set repo_dir [file normalize [env_or THEMIS_SOURCE_REPO [file join $script_dir ..]]]
set build_root [file normalize [env_or THEMIS_EVAL_BUILD_ROOT [file join $repo_dir build themis_hbm_core_eval]]]
set part_name [env_or THEMIS_EVAL_PART xcu200-fsgd2104-2-e]
set clk_period_ns [env_or THEMIS_EVAL_CLK_PERIOD_NS 3.333]
set cores [env_or THEMIS_EVAL_CORES 1]
set data_width [env_or THEMIS_EVAL_DATA_WIDTH 512]
set cell_ptr_width [env_or THEMIS_EVAL_CELL_PTR_WIDTH 3]
set heap_bitmap_width [env_or THEMIS_EVAL_HEAP_BITMAP_WIDTH 8]

file mkdir $build_root

set rtl_files [list \
  [file join $repo_dir hbm rtl common heap_ops.sv] \
  [file join $repo_dir hbm rtl common ffs.sv] \
  [file join $repo_dir hbm rtl common themis_memory_primitives.sv] \
  [file join $repo_dir hbm rtl core bbq.sv] \
  [file join $repo_dir hbm rtl core themis_linked_buffer_manager.sv] \
  [file join $script_dir themis_replicated_eval_top.sv] \
]

puts "Themis HBM source core synthesis configuration:"
puts "  repo=$repo_dir"
puts "  build_root=$build_root"
puts "  cores=$cores data_width=$data_width cell_ptr_width=$cell_ptr_width heap_bitmap_width=$heap_bitmap_width"
puts "  part=$part_name clk_period_ns=$clk_period_ns"

read_verilog -sv $rtl_files
synth_design -top themis_replicated_eval_top -part $part_name -mode out_of_context \
  -generic CORES=$cores \
  -generic DATA_WIDTH=$data_width \
  -generic CELL_PTR_WIDTH=$cell_ptr_width \
  -generic HEAP_BITMAP_WIDTH=$heap_bitmap_width
create_clock -period $clk_period_ns -name clk [get_ports clk]

set util_report [file join $build_root themis_hbm_core_utilization_synth.rpt]
set hier_report [file join $build_root themis_hbm_core_utilization_hier_synth.rpt]
set timing_report [file join $build_root themis_hbm_core_timing_summary_synth.rpt]
report_utilization -file $util_report
report_utilization -hierarchical -file $hier_report
report_timing_summary -max_paths 10 -file $timing_report

set lut [parse_util_metric $util_report "CLB LUTs"]
set ff [parse_util_metric $util_report "CLB Registers"]
set lutram [parse_util_metric $util_report "LUT as Memory"]
set bram [parse_util_metric $util_report "Block RAM Tile"]
set uram [parse_util_metric $util_report "URAM"]
set dsp [parse_util_metric $util_report "DSPs"]
set wns [parse_wns $timing_report]

set csv_path [file join $build_root themis_hbm_core_resource.csv]
set csv [open $csv_path w]
puts $csv "design,cores,data_width,cell_ptr_width,heap_bitmap_width,clb_luts,clb_registers,lutram,bram_tiles,uram,dsps,wns_ns"
puts $csv "Themis-HBM-source,$cores,$data_width,$cell_ptr_width,$heap_bitmap_width,$lut,$ff,$lutram,$bram,$uram,$dsp,$wns"
close $csv

puts "Themis HBM source utilization: $util_report"
puts "Themis HBM source hierarchical utilization: $hier_report"
puts "Themis HBM source timing summary: $timing_report"
puts "Themis HBM source cores=$cores: LUT=$lut FF=$ff LUTRAM=$lutram BRAM=$bram URAM=$uram DSP=$dsp WNS=$wns"
exit 0
