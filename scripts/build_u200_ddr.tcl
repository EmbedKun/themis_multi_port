set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set build_root [expr {[info exists ::env(HESTIA_BUILD_ROOT)] && $::env(HESTIA_BUILD_ROOT) ne "" ? [file normalize $::env(HESTIA_BUILD_ROOT)] : [file join $repo_dir build hestia_u200_ddr]}]
set build_dir [file join $build_root vivado]
file mkdir $build_dir

set project_name hestia_u200_ddr
set bd_name hestia_u200_bd
create_project -force $project_name $build_dir -part xcu200-fsgd2104-2-e
set_property board_part xilinx.com:au200:part0:1.3 [current_project]
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set sv_files [list \
  [file join $repo_dir rtl hestia_pkg.sv] \
  [file join $repo_dir rtl hestia_port_bbq.sv] \
  [file join $repo_dir rtl hestia_core_ddr_bbq.sv] \
  [file join $repo_dir rtl hestia_synthetic_packet_gen.sv] \
  [file join $repo_dir rtl hestia_u200_top.sv] \
]
set v_files [list \
  [file join $repo_dir rtl hestia_u200_bd_cell.v] \
]
add_files -fileset sources_1 $sv_files
add_files -fileset sources_1 $v_files
set_property file_type SystemVerilog [get_files $sv_files]

create_bd_design $bd_name
current_bd_design $bd_name

create_bd_cell -type module -reference hestia_u200_bd_cell mp_top

proc themis_env_or {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

set u200_ports [themis_env_or HESTIA_U200_PORTS 8]
set u200_rank_width [themis_env_or HESTIA_U200_RANK_WIDTH 10]
set u200_seq_width [themis_env_or HESTIA_U200_SEQ_WIDTH 32]
set u200_payload_width [themis_env_or HESTIA_U200_PAYLOAD_WIDTH 64]
set u200_sram_cells [themis_env_or HESTIA_U200_SRAM_CELLS 64]
set u200_batch_size [themis_env_or HESTIA_U200_BATCH_SIZE 4]
set u200_batch_slots [themis_env_or HESTIA_U200_BATCH_SLOTS 16]
set u200_port_queue_depth [themis_env_or HESTIA_U200_PORT_QUEUE_DEPTH 64]
set u200_packet_slots [themis_env_or HESTIA_U200_PACKET_SLOTS [expr {$u200_port_queue_depth * $u200_ports}]]
set u200_bbq_bitmap_width [themis_env_or HESTIA_U200_BBQ_BITMAP_WIDTH [expr {$u200_rank_width <= 8 ? 16 : 32}]]
set u200_cell_count_width [themis_env_or HESTIA_U200_CELL_COUNT_WIDTH 4]
set u200_max_cell_count [themis_env_or HESTIA_U200_MAX_CELL_COUNT 4]
set u200_cell_count_mode [themis_env_or HESTIA_U200_CELL_COUNT_MODE 1]
set u200_max_packets [themis_env_or HESTIA_U200_MAX_PACKETS 128]
set u200_gen_period [themis_env_or HESTIA_U200_GEN_PERIOD_CYCLES 1]
set u200_drain_after_gen [themis_env_or HESTIA_U200_DRAIN_AFTER_GENERATION_ONLY 1]
set u200_drain_start_packets [themis_env_or HESTIA_U200_DRAIN_START_PACKETS 0]
set u200_drain_period [themis_env_or HESTIA_U200_DRAIN_PERIOD_CYCLES 1]
set u200_rank_dist [themis_env_or HESTIA_U200_RANK_DIST 0]
set u200_high_priority [themis_env_or HESTIA_U200_HIGH_PRIORITY_PER1024 256]
set u200_swap_in_threshold [themis_env_or HESTIA_U200_SWAP_IN_THRESHOLD 16]
set u200_swap_out_threshold [themis_env_or HESTIA_U200_SWAP_OUT_THRESHOLD 48]
set u200_test_mode [themis_env_or HESTIA_U200_TEST_MODE 0]
set u200_allow_drops [themis_env_or HESTIA_U200_ALLOW_DROPS 0]
set u200_core_clk_mhz [themis_env_or HESTIA_U200_CORE_CLK_MHZ 0]
puts "Hestia U200 self-test: ports=${u200_ports} rank_width=${u200_rank_width} SRAM=${u200_sram_cells} batch_size=${u200_batch_size} batch_slots=${u200_batch_slots} packet_slots=${u200_packet_slots} bbq_bitmap=${u200_bbq_bitmap_width} cell_width=${u200_cell_count_width} max_cell=${u200_max_cell_count} cell_mode=${u200_cell_count_mode} max_packets=${u200_max_packets} drain_after_gen=${u200_drain_after_gen} drain_start_packets=${u200_drain_start_packets} drain_period=${u200_drain_period} swap_in=${u200_swap_in_threshold} swap_out=${u200_swap_out_threshold} test_mode=${u200_test_mode} allow_drops=${u200_allow_drops} core_clk_mhz=${u200_core_clk_mhz}"
set_property -dict [list \
  CONFIG.PORTS $u200_ports \
  CONFIG.RANK_WIDTH $u200_rank_width \
  CONFIG.SEQ_WIDTH $u200_seq_width \
  CONFIG.PAYLOAD_WIDTH $u200_payload_width \
  CONFIG.SRAM_CELLS $u200_sram_cells \
  CONFIG.BATCH_SIZE $u200_batch_size \
  CONFIG.BATCH_SLOTS $u200_batch_slots \
  CONFIG.PORT_QUEUE_DEPTH $u200_port_queue_depth \
  CONFIG.PACKET_SLOTS $u200_packet_slots \
  CONFIG.BBQ_BITMAP_WIDTH $u200_bbq_bitmap_width \
  CONFIG.CELL_COUNT_WIDTH $u200_cell_count_width \
  CONFIG.MAX_CELL_COUNT $u200_max_cell_count \
  CONFIG.CELL_COUNT_MODE $u200_cell_count_mode \
  CONFIG.MAX_PACKETS $u200_max_packets \
  CONFIG.GEN_PERIOD_CYCLES $u200_gen_period \
  CONFIG.DRAIN_AFTER_GENERATION_ONLY $u200_drain_after_gen \
  CONFIG.DRAIN_START_PACKETS $u200_drain_start_packets \
  CONFIG.DRAIN_PERIOD_CYCLES $u200_drain_period \
  CONFIG.RANK_DIST $u200_rank_dist \
  CONFIG.HIGH_PRIORITY_PER1024 $u200_high_priority \
  CONFIG.SWAP_IN_THRESHOLD $u200_swap_in_threshold \
  CONFIG.SWAP_OUT_THRESHOLD $u200_swap_out_threshold \
  CONFIG.TEST_MODE $u200_test_mode \
  CONFIG.ALLOW_DROPS $u200_allow_drops \
] [get_bd_cells mp_top]

set ddr_timeperiod_ps 833
if {[info exists ::env(HESTIA_DDR_TIMEPERIOD_PS)] && $::env(HESTIA_DDR_TIMEPERIOD_PS) ne ""} {
  set ddr_timeperiod_ps $::env(HESTIA_DDR_TIMEPERIOD_PS)
}
set ddr_clkout0_divide 5
if {[info exists ::env(HESTIA_DDR_CLKOUT0_DIVIDE)] && $::env(HESTIA_DDR_CLKOUT0_DIVIDE) ne ""} {
  set ddr_clkout0_divide $::env(HESTIA_DDR_CLKOUT0_DIVIDE)
}
puts "Hestia U200 DDR4 time period: ${ddr_timeperiod_ps} ps clkout0_divide=${ddr_clkout0_divide}"

create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4 ddr4_0
set ddr4_props [list \
  CONFIG.C0_DDR4_BOARD_INTERFACE ddr4_sdram_c0 \
  CONFIG.C0_CLOCK_BOARD_INTERFACE default_300mhz_clk0 \
  CONFIG.C0.DDR4_AxiAddressWidth {34} \
  CONFIG.C0.DDR4_AxiDataWidth {512} \
  CONFIG.C0.DDR4_AxiIDWidth {4} \
  CONFIG.C0.DDR4_CLKOUT0_DIVIDE $ddr_clkout0_divide \
  CONFIG.C0.DDR4_DataWidth {72} \
  CONFIG.C0.DDR4_Ecc {true} \
  CONFIG.C0.DDR4_InputClockPeriod {3332} \
  CONFIG.C0.DDR4_MemoryPart {MTA18ASF2G72PZ-2G3} \
  CONFIG.C0.DDR4_MemoryType {RDIMMs} \
  CONFIG.C0.DDR4_TimePeriod $ddr_timeperiod_ps \
  CONFIG.C0.DDR4_AUTO_AP_COL_A3 {true} \
  CONFIG.C0.DDR4_Mem_Add_Map {ROW_COLUMN_BANK_INTLV} \
]
if {$u200_core_clk_mhz > 0} {
  lappend ddr4_props CONFIG.ADDN_UI_CLKOUT1_FREQ_HZ $u200_core_clk_mhz
}
set_property -dict $ddr4_props [get_bd_cells ddr4_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_register_slice axi_reg
set_property -dict [list CONFIG.ADDR_WIDTH {34} CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {4}] [get_bd_cells axi_reg]
if {$u200_core_clk_mhz > 0} {
  create_bd_cell -type ip -vlnv xilinx.com:ip:axi_clock_converter axi_clkconv
  set_property -dict [list CONFIG.ADDR_WIDTH {34} CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {4}] [get_bd_cells axi_clkconv]
  create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_core
}
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_ddr
create_bd_cell -type ip -vlnv xilinx.com:ip:jtag_axi ctrl_jtag_axi
set_property -dict [list CONFIG.PROTOCOL {2} CONFIG.M_AXI_ADDR_WIDTH {32} CONFIG.M_AXI_DATA_WIDTH {32}] [get_bd_cells ctrl_jtag_axi]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant sys_rst_const
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] [get_bd_cells sys_rst_const]

apply_bd_automation -rule xilinx.com:bd_rule:board -config {Board_Interface "ddr4_sdram_c0"} [get_bd_intf_pins ddr4_0/C0_DDR4]
apply_bd_automation -rule xilinx.com:bd_rule:board -config {Board_Interface "default_300mhz_clk0"} [get_bd_intf_pins ddr4_0/C0_SYS_CLK]

set ddr_ui_clk_pin [get_bd_pins ddr4_0/c0_ddr4_ui_clk]
set core_clk_pin $ddr_ui_clk_pin
if {$u200_core_clk_mhz > 0} {
  set core_clk_pin [get_bd_pins ddr4_0/addn_ui_clkout1]
}

connect_bd_net $ddr_ui_clk_pin [get_bd_pins axi_reg/aclk] [get_bd_pins rst_ddr/slowest_sync_clk] [get_bd_pins ctrl_jtag_axi/aclk]
if {$u200_core_clk_mhz > 0} {
  connect_bd_net $core_clk_pin [get_bd_pins mp_top/clk] [get_bd_pins rst_core/slowest_sync_clk] [get_bd_pins axi_clkconv/s_axi_aclk]
  connect_bd_net $ddr_ui_clk_pin [get_bd_pins axi_clkconv/m_axi_aclk]
} else {
  connect_bd_net $ddr_ui_clk_pin [get_bd_pins mp_top/clk]
}
connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk_sync_rst] [get_bd_pins rst_ddr/ext_reset_in]
if {$u200_core_clk_mhz > 0} {
  connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk_sync_rst] [get_bd_pins rst_core/ext_reset_in]
}
connect_bd_net [get_bd_pins sys_rst_const/dout] [get_bd_pins ddr4_0/sys_rst]
if {$u200_core_clk_mhz > 0} {
  connect_bd_net [get_bd_pins rst_ddr/peripheral_aresetn] [get_bd_pins axi_reg/aresetn] [get_bd_pins ddr4_0/c0_ddr4_aresetn] [get_bd_pins ctrl_jtag_axi/aresetn] [get_bd_pins axi_clkconv/m_axi_aresetn]
  connect_bd_net [get_bd_pins rst_core/peripheral_aresetn] [get_bd_pins mp_top/resetn] [get_bd_pins axi_clkconv/s_axi_aresetn]
} else {
  connect_bd_net [get_bd_pins rst_ddr/peripheral_aresetn] [get_bd_pins mp_top/resetn] [get_bd_pins axi_reg/aresetn] [get_bd_pins ddr4_0/c0_ddr4_aresetn] [get_bd_pins ctrl_jtag_axi/aresetn]
}
connect_bd_net [get_bd_pins ddr4_0/c0_init_calib_complete] [get_bd_pins mp_top/calib_done]
if {$u200_core_clk_mhz > 0} {
  connect_bd_intf_net [get_bd_intf_pins mp_top/M_AXI] [get_bd_intf_pins axi_clkconv/S_AXI]
  connect_bd_intf_net [get_bd_intf_pins axi_clkconv/M_AXI] [get_bd_intf_pins axi_reg/S_AXI]
} else {
  connect_bd_intf_net [get_bd_intf_pins mp_top/M_AXI] [get_bd_intf_pins axi_reg/S_AXI]
}
connect_bd_intf_net [get_bd_intf_pins axi_reg/M_AXI] [get_bd_intf_pins ddr4_0/C0_DDR4_S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_jtag_axi/M_AXI] [get_bd_intf_pins ddr4_0/C0_DDR4_S_AXI_CTRL]

set enable_ila 1
if {[info exists ::env(HESTIA_ENABLE_ILA)] && $::env(HESTIA_ENABLE_ILA) ne ""} {
  set enable_ila $::env(HESTIA_ENABLE_ILA)
}
if {$enable_ila} {
  set ila_depth 2048
  if {[info exists ::env(HESTIA_ILA_DEPTH)] && $::env(HESTIA_ILA_DEPTH) ne ""} {
    set ila_depth $::env(HESTIA_ILA_DEPTH)
  }
  set ila_light 0
  if {[info exists ::env(HESTIA_ILA_LIGHT)] && $::env(HESTIA_ILA_LIGHT) ne ""} {
    set ila_light $::env(HESTIA_ILA_LIGHT)
  }
  create_bd_cell -type ip -vlnv xilinx.com:ip:ila hestia_ila
  if {$ila_light} {
    set_property CONFIG.C_NUM_OF_PROBES {5} [get_bd_cells hestia_ila]
    set_property -dict [list \
      CONFIG.C_DATA_DEPTH $ila_depth \
      CONFIG.C_PROBE0_WIDTH {512} \
      CONFIG.C_PROBE1_WIDTH {1} \
      CONFIG.C_PROBE2_WIDTH {1} \
      CONFIG.C_PROBE3_WIDTH {1} \
      CONFIG.C_PROBE4_WIDTH {1} \
    ] [get_bd_cells hestia_ila]
  } else {
    set_property CONFIG.C_NUM_OF_PROBES {8} [get_bd_cells hestia_ila]
    set_property -dict [list \
      CONFIG.C_DATA_DEPTH $ila_depth \
      CONFIG.C_PROBE0_WIDTH {768} \
      CONFIG.C_PROBE1_WIDTH {1} \
      CONFIG.C_PROBE2_WIDTH {1} \
      CONFIG.C_PROBE3_WIDTH {1} \
      CONFIG.C_PROBE4_WIDTH {8} \
      CONFIG.C_PROBE5_WIDTH {32} \
      CONFIG.C_PROBE6_WIDTH {32} \
      CONFIG.C_PROBE7_WIDTH {1} \
    ] [get_bd_cells hestia_ila]
  }
  connect_bd_net $core_clk_pin [get_bd_pins hestia_ila/clk]
  if {$ila_light} {
    connect_bd_net [get_bd_pins mp_top/dbg_light_bus] [get_bd_pins hestia_ila/probe0]
    connect_bd_net [get_bd_pins mp_top/done] [get_bd_pins hestia_ila/probe1]
    connect_bd_net [get_bd_pins mp_top/dbg_ddr_wr_error] [get_bd_pins hestia_ila/probe2]
    connect_bd_net [get_bd_pins mp_top/dbg_ddr_rd_error] [get_bd_pins hestia_ila/probe3]
    connect_bd_net [get_bd_pins mp_top/calib_done_sync_dbg] [get_bd_pins hestia_ila/probe4]
  } else {
    connect_bd_net [get_bd_pins mp_top/dbg_bus] [get_bd_pins hestia_ila/probe0]
    connect_bd_net [get_bd_pins mp_top/done] [get_bd_pins hestia_ila/probe1]
    connect_bd_net [get_bd_pins mp_top/dbg_ddr_wr_error] [get_bd_pins hestia_ila/probe2]
    connect_bd_net [get_bd_pins mp_top/dbg_ddr_rd_error] [get_bd_pins hestia_ila/probe3]
    connect_bd_net [get_bd_pins mp_top/dbg_ddr_state] [get_bd_pins hestia_ila/probe4]
    connect_bd_net [get_bd_pins mp_top/dbg_generated] [get_bd_pins hestia_ila/probe5]
    connect_bd_net [get_bd_pins mp_top/dbg_dequeued] [get_bd_pins hestia_ila/probe6]
    connect_bd_net [get_bd_pins mp_top/calib_done_sync_dbg] [get_bd_pins hestia_ila/probe7]
  }
}

set cdc_xdc [file join $build_dir hestia_u200_cdc.xdc]
set cdc_fp [open $cdc_xdc w]
puts $cdc_fp {set_false_path -to [get_pins -hierarchical -filter {NAME =~ *calib_done_meta_reg/D}]}
close $cdc_fp
add_files -fileset constrs_1 $cdc_xdc

assign_bd_address
validate_bd_design
save_bd_design
make_wrapper -files [get_files [file join $build_dir $project_name.srcs sources_1 bd $bd_name ${bd_name}.bd]] -top
add_files -norecurse [file join $build_dir $project_name.gen sources_1 bd $bd_name hdl ${bd_name}_wrapper.v]
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

if {[info exists ::env(HESTIA_STOP_AFTER_PROJECT)] && $::env(HESTIA_STOP_AFTER_PROJECT) ne "" && $::env(HESTIA_STOP_AFTER_PROJECT)} {
  puts "Hestia U200 project created: [file join $build_dir $project_name.xpr]"
  exit 0
}

set jobs 1
if {[info exists ::env(HESTIA_VIVADO_JOBS)] && $::env(HESTIA_VIVADO_JOBS) ne ""} {
  set jobs $::env(HESTIA_VIVADO_JOBS)
}

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "Hestia U200 synthesis status: $synth_status"
if {[string first "synth_design Complete" $synth_status] < 0} {
  exit 1
}

if {[info exists ::env(HESTIA_STOP_AFTER_SYNTH)] && $::env(HESTIA_STOP_AFTER_SYNTH) ne "" && $::env(HESTIA_STOP_AFTER_SYNTH)} {
  exit 0
}

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "Hestia U200 implementation status: $impl_status"
if {[string first "write_bitstream Complete" $impl_status] < 0} {
  exit 1
}

set bitfiles [glob -nocomplain [file join $build_dir $project_name.runs impl_1 *.bit]]
set ltxfiles [glob -nocomplain [file join $build_dir $project_name.runs impl_1 *.ltx]]
if {[llength $bitfiles] > 0} {
  puts "Hestia U200 bitstream: [lindex $bitfiles 0]"
}
if {[llength $ltxfiles] > 0} {
  puts "Hestia U200 probes: [lindex $ltxfiles 0]"
}
exit 0
