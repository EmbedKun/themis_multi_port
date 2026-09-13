set script_dir [file dirname [file normalize [info script]]]
set handoff_dir [file normalize [file join $script_dir ..]]
set repo_dir [file normalize [file join $handoff_dir ..]]

proc env_or {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
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

set ports [env_or HESTIA_ASIC_PORTS 4]
set policy_mode [env_or HESTIA_ASIC_POLICY_MODE -1]
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
set sdc_file [env_or HESTIA_ASIC_SDC [file join $handoff_dir constraints hestia_1ghz.sdc]]
set report_dir [env_or HESTIA_ASIC_REPORT_DIR [file join $repo_dir build dc_asic_logic_only]]
file mkdir $report_dir

if {[info exists ::env(TARGET_LIBRARY)]} {
  set_app_var target_library $::env(TARGET_LIBRARY)
}
if {[info exists ::env(LINK_LIBRARY)]} {
  set_app_var link_library $::env(LINK_LIBRARY)
}

set rtl_files [read_filelist $repo_dir [file join $handoff_dir filelists hestia_asic_logic_only.f]]
analyze -format sverilog $rtl_files
elaborate hestia_asic_core -parameters "PORTS=$ports,RANK_WIDTH=$rank_width,SEQ_WIDTH=$seq_width,PAYLOAD_WIDTH=$payload_width,CELL_COUNT_WIDTH=$cell_count_width,AXI_ADDR_WIDTH=$axi_addr_width,AXI_DATA_WIDTH=$axi_data_width,AXI_ID_WIDTH=$axi_id_width,SRAM_CELLS=$sram_cells,BATCH_SIZE=$batch_size,BATCH_SLOTS=$batch_slots,PACKET_SLOTS=$packet_slots,BBQ_BITMAP_WIDTH=$bbq_bitmap_width,POLICY_MODE=$policy_mode,POLICY_ALPHA_SHIFT=$policy_alpha_shift"
current_design hestia_asic_core
link
check_design > [file join $report_dir check_design.rpt]

source $sdc_file
set_dont_touch [get_cells -hier -filter "ref_name == hestia_asic_sram_1r1w"] true

compile_ultra

report_area -hierarchy > [file join $report_dir area_hier.rpt]
report_timing -max_paths 20 > [file join $report_dir timing.rpt]
report_power > [file join $report_dir power.rpt]
write -format verilog -hierarchy -output [file join $report_dir hestia_asic_core_mapped.v]

quit
