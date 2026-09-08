set script_dir [file dirname [file normalize [info script]]]
set handoff_dir [file normalize [file join $script_dir ..]]
set repo_dir [file normalize [file join $handoff_dir ..]]

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

proc policy_name {policy} {
  switch -- $policy {
    -1 { return "Hestia" }
    0  { return "DT-Hybrid" }
    1  { return "Occamy-Hybrid" }
    3  { return "OBM-Hybrid" }
    4  { return "Hybrid-Themis" }
    default { return "unknown" }
  }
}

proc read_filelist {repo_dir filelist_path} {
  set fh [open $filelist_path r]
  set files [list]
  while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq ""} {
      continue
    }
    if {[string index $line 0] eq "#"} {
      continue
    }
    lappend files [file normalize [file join $repo_dir $line]]
  }
  close $fh
  return $files
}

if {[llength $argv] > 0} {
  set build_root [file normalize [lindex $argv 0]]
} else {
  set build_root [file join $repo_dir build asic_logic_only]
}
if {[llength $argv] > 1} {
  set clk_period_ns [lindex $argv 1]
} else {
  set clk_period_ns [env_or HESTIA_ASIC_CLK_PERIOD_NS 3.333]
}
file mkdir $build_root

set part_name [env_or HESTIA_ASIC_VIVADO_PART xcu200-fsgd2104-2-e]
set ports [env_or HESTIA_ASIC_PORTS 4]
set policy_mode [env_or HESTIA_ASIC_POLICY_MODE -1]
set design_name [env_or HESTIA_ASIC_DESIGN_NAME [policy_name $policy_mode]]
set rank_width [env_or HESTIA_ASIC_RANK_WIDTH 10]
set seq_width [env_or HESTIA_ASIC_SEQ_WIDTH 16]
set payload_width [env_or HESTIA_ASIC_PAYLOAD_WIDTH 32]
set cell_count_width [env_or HESTIA_ASIC_CELL_COUNT_WIDTH 27]
set axi_addr_width [env_or HESTIA_ASIC_AXI_ADDR_WIDTH 64]
set axi_data_width [env_or HESTIA_ASIC_AXI_DATA_WIDTH 512]
set axi_id_width [env_or HESTIA_ASIC_AXI_ID_WIDTH 4]
set sram_cells [env_or HESTIA_ASIC_SRAM_CELLS 81920]
set batch_size [env_or HESTIA_ASIC_BATCH_SIZE 8]
set batch_slots [env_or HESTIA_ASIC_BATCH_SLOTS 8388608]
set packet_slots [env_or HESTIA_ASIC_PACKET_SLOTS 81920]
set bbq_bitmap_width [env_or HESTIA_ASIC_BBQ_BITMAP_WIDTH 32]
set policy_alpha_shift [env_or HESTIA_ASIC_POLICY_ALPHA_SHIFT 0]

puts "Hestia ASIC logic-only synthesis:"
puts "  design=${design_name} policy=${policy_mode} ports=${ports}"
puts "  SRAM cells=${sram_cells} batch_size=${batch_size} batch_slots=${batch_slots} packet_slots=${packet_slots}"
puts "  memory mode=black-box SRAM macros, DDR controller/PHY excluded"

set filelist_path [file join $handoff_dir filelists hestia_asic_logic_only.f]
set rtl_files [read_filelist $repo_dir $filelist_path]

read_verilog -sv $rtl_files
synth_design -top hestia_asic_core -part $part_name -mode out_of_context \
  -generic PORTS=$ports \
  -generic RANK_WIDTH=$rank_width \
  -generic SEQ_WIDTH=$seq_width \
  -generic PAYLOAD_WIDTH=$payload_width \
  -generic CELL_COUNT_WIDTH=$cell_count_width \
  -generic AXI_ADDR_WIDTH=$axi_addr_width \
  -generic AXI_DATA_WIDTH=$axi_data_width \
  -generic AXI_ID_WIDTH=$axi_id_width \
  -generic SRAM_CELLS=$sram_cells \
  -generic BATCH_SIZE=$batch_size \
  -generic BATCH_SLOTS=$batch_slots \
  -generic PACKET_SLOTS=$packet_slots \
  -generic BBQ_BITMAP_WIDTH=$bbq_bitmap_width \
  -generic POLICY_MODE=$policy_mode \
  -generic POLICY_ALPHA_SHIFT=$policy_alpha_shift

create_clock -period $clk_period_ns -name clk [get_ports clk]

set util_report [file join $build_root asic_logic_only_utilization_synth.rpt]
set hier_report [file join $build_root asic_logic_only_utilization_hier_synth.rpt]
set timing_report [file join $build_root asic_logic_only_timing_summary_synth.rpt]
set checkpoint_path [file join $build_root asic_logic_only_synth.dcp]
report_utilization -file $util_report
report_utilization -hierarchical -file $hier_report
report_timing_summary -max_paths 10 -file $timing_report
write_checkpoint -force $checkpoint_path

set lut [parse_util_metric $util_report "CLB LUTs"]
set ff [parse_util_metric $util_report "CLB Registers"]
set lutram [parse_util_metric $util_report "LUT as Memory"]
set bram [parse_util_metric $util_report "Block RAM Tile"]
set uram [parse_util_metric $util_report "URAM"]
set dsp [parse_util_metric $util_report "DSPs"]
set wns [parse_wns $timing_report]
set blackbox_count ""
if {![catch {get_cells -hier -filter {IS_BLACKBOX == 1}} bb_cells]} {
  set blackbox_count [llength $bb_cells]
}

set csv_path [file join $build_root asic_logic_only_resource.csv]
set csv [open $csv_path w]
puts $csv "design,policy_mode,ports,rank_width,seq_width,cell_count_width,sram_cells,batch_size,batch_slots,packet_slots,bbq_bitmap_width,clb_luts,clb_registers,lutram,bram_tiles,uram,dsps,wns_ns,blackbox_memories"
puts $csv "$design_name,$policy_mode,$ports,$rank_width,$seq_width,$cell_count_width,$sram_cells,$batch_size,$batch_slots,$packet_slots,$bbq_bitmap_width,$lut,$ff,$lutram,$bram,$uram,$dsp,$wns,$blackbox_count"
close $csv

puts "ASIC logic-only utilization: $util_report"
puts "ASIC logic-only hierarchical utilization: $hier_report"
puts "ASIC logic-only timing summary: $timing_report"
puts "ASIC logic-only CSV: $csv_path"
puts "RESULT design=${design_name} policy=${policy_mode} ports=${ports} LUT=${lut} FF=${ff} LUTRAM=${lutram} BRAM=${bram} URAM=${uram} DSP=${dsp} WNS=${wns} BLACKBOX=${blackbox_count}"
exit 0
