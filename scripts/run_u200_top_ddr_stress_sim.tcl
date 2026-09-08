set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
if {[llength $argv] > 0} {
  set build_root [file normalize [lindex $argv 0]]
} elseif {[info exists ::env(HESTIA_U200_TOP_DDR_STRESS_BUILD_ROOT)] && $::env(HESTIA_U200_TOP_DDR_STRESS_BUILD_ROOT) ne ""} {
  set build_root [file normalize $::env(HESTIA_U200_TOP_DDR_STRESS_BUILD_ROOT)]
} else {
  set build_root [file join $repo_dir build hestia_u200_top_ddr_stress_sim]
}
file mkdir $build_root

proc themis_env_or {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

set stress_max_packets [themis_env_or HESTIA_STRESS_MAX_PACKETS 4096]
set stress_ports [themis_env_or HESTIA_STRESS_PORTS 8]
set stress_rank_width [themis_env_or HESTIA_STRESS_RANK_WIDTH 10]
set stress_bbq_bitmap_width [themis_env_or HESTIA_STRESS_BBQ_BITMAP_WIDTH 32]
set stress_sram_cells [themis_env_or HESTIA_STRESS_SRAM_CELLS 32]
set stress_batch_size [themis_env_or HESTIA_STRESS_BATCH_SIZE 8]
set stress_batch_slots [themis_env_or HESTIA_STRESS_BATCH_SLOTS 128]
set stress_port_queue_depth [themis_env_or HESTIA_STRESS_PORT_QUEUE_DEPTH 256]
set stress_packet_slots [themis_env_or HESTIA_STRESS_PACKET_SLOTS 512]
set stress_cell_count_width [themis_env_or HESTIA_STRESS_CELL_COUNT_WIDTH 4]
set stress_max_cell_count [themis_env_or HESTIA_STRESS_MAX_CELL_COUNT 4]
set stress_cell_count_mode [themis_env_or HESTIA_STRESS_CELL_COUNT_MODE 1]
set stress_gen_period_cycles [themis_env_or HESTIA_STRESS_GEN_PERIOD_CYCLES 1]
set stress_drain_start_packets [themis_env_or HESTIA_STRESS_DRAIN_START_PACKETS 256]
set stress_drain_period_cycles [themis_env_or HESTIA_STRESS_DRAIN_PERIOD_CYCLES 3]
set stress_rank_dist [themis_env_or HESTIA_STRESS_RANK_DIST 3]
set stress_swap_in_threshold [themis_env_or HESTIA_STRESS_SWAP_IN_THRESHOLD 16]
set stress_swap_out_threshold [themis_env_or HESTIA_STRESS_SWAP_OUT_THRESHOLD 24]
set stress_timeout_cycles [themis_env_or HESTIA_STRESS_TIMEOUT_CYCLES 3000000]
set stress_min_ddr_write_batches [themis_env_or HESTIA_STRESS_MIN_DDR_WRITE_BATCHES 8]
set stress_min_direct_ddr_dequeue [themis_env_or HESTIA_STRESS_MIN_DIRECT_DDR_DEQUEUE 8]
set stress_min_ddr_write_beats [themis_env_or HESTIA_STRESS_MIN_DDR_WRITE_BEATS 64]
set stress_min_ddr_read_beats [themis_env_or HESTIA_STRESS_MIN_DDR_READ_BEATS 64]

set rtl_files [list \
  [file join $repo_dir rtl hestia_pkg.sv] \
  [file join $repo_dir rtl hestia_port_rank_queue.sv] \
  [file join $repo_dir rtl hestia_port_bbq.sv] \
  [file join $repo_dir rtl hestia_policy_dt.sv] \
  [file join $repo_dir rtl hestia_policy_occamy.sv] \
  [file join $repo_dir rtl hestia_policy_obm.sv] \
  [file join $repo_dir rtl hestia_core_ddr.sv] \
  [file join $repo_dir rtl hestia_core_ddr_bbq.sv] \
  [file join $repo_dir rtl hestia_synthetic_packet_gen.sv] \
  [file join $repo_dir rtl hestia_u200_top.sv] \
]
set sim_files [list \
  [file join $repo_dir sim tb_hestia_ddr.sv] \
  [file join $repo_dir sim tb_hestia_u200_top_ddr_stress.sv] \
]
set glbl_file [file join $::env(XILINX_VIVADO) data verilog src glbl.v]

set xvlog_defs [list \
  -d MP_STRESS_MAX_PACKETS=$stress_max_packets \
  -d MP_STRESS_PORTS=$stress_ports \
  -d MP_STRESS_RANK_WIDTH=$stress_rank_width \
  -d MP_STRESS_BBQ_BITMAP_WIDTH=$stress_bbq_bitmap_width \
  -d MP_STRESS_SRAM_CELLS=$stress_sram_cells \
  -d MP_STRESS_BATCH_SIZE=$stress_batch_size \
  -d MP_STRESS_BATCH_SLOTS=$stress_batch_slots \
  -d MP_STRESS_PORT_QUEUE_DEPTH=$stress_port_queue_depth \
  -d MP_STRESS_PACKET_SLOTS=$stress_packet_slots \
  -d MP_STRESS_CELL_COUNT_WIDTH=$stress_cell_count_width \
  -d MP_STRESS_MAX_CELL_COUNT=$stress_max_cell_count \
  -d MP_STRESS_CELL_COUNT_MODE=$stress_cell_count_mode \
  -d MP_STRESS_GEN_PERIOD_CYCLES=$stress_gen_period_cycles \
  -d MP_STRESS_DRAIN_START_PACKETS=$stress_drain_start_packets \
  -d MP_STRESS_DRAIN_PERIOD_CYCLES=$stress_drain_period_cycles \
  -d MP_STRESS_RANK_DIST=$stress_rank_dist \
  -d MP_STRESS_SWAP_IN_THRESHOLD=$stress_swap_in_threshold \
  -d MP_STRESS_SWAP_OUT_THRESHOLD=$stress_swap_out_threshold \
  -d MP_STRESS_TIMEOUT_CYCLES=$stress_timeout_cycles \
  -d MP_STRESS_MIN_DDR_WRITE_BATCHES=$stress_min_ddr_write_batches \
  -d MP_STRESS_MIN_DIRECT_DDR_DEQUEUE=$stress_min_direct_ddr_dequeue \
  -d MP_STRESS_MIN_DDR_WRITE_BEATS=$stress_min_ddr_write_beats \
  -d MP_STRESS_MIN_DDR_READ_BEATS=$stress_min_ddr_read_beats \
]

set old_dir [pwd]
cd $build_root
file delete -force xsim.dir xvlog.log xelab.log simulate.log webtalk.log

set xvlog_sv_cmd [concat [list xvlog --sv --relax] $xvlog_defs $rtl_files $sim_files]
puts "Running: $xvlog_sv_cmd"
if {[catch {exec {*}$xvlog_sv_cmd >@ stdout 2>@ stderr} result]} {
  puts "ERROR: xvlog SystemVerilog compile failed: $result"
  cd $old_dir
  exit 1
}

set xvlog_glbl_cmd [list xvlog --relax $glbl_file]
puts "Running: $xvlog_glbl_cmd"
if {[catch {exec {*}$xvlog_glbl_cmd >@ stdout 2>@ stderr} result]} {
  puts "ERROR: xvlog glbl compile failed: $result"
  cd $old_dir
  exit 1
}

set xelab_cmd [list xelab --debug off --relax --mt 8 -L work -L unisims_ver -L unimacro_ver -L secureip -s tb_hestia_u200_top_ddr_stress_behav work.tb_hestia_u200_top_ddr_stress work.glbl]
puts "Running: $xelab_cmd"
if {[catch {exec {*}$xelab_cmd >@ stdout 2>@ stderr} result]} {
  puts "ERROR: xelab failed: $result"
  cd $old_dir
  exit 1
}

set run_fh [open [file join $build_root xsim_run.tcl] w]
puts $run_fh "run -all"
puts $run_fh "quit"
close $run_fh

set xsim_cmd [list xsim tb_hestia_u200_top_ddr_stress_behav -wdb /dev/null -tclbatch [file join $build_root xsim_run.tcl] -log simulate.log]
puts "Running: $xsim_cmd"
if {[catch {exec {*}$xsim_cmd >@ stdout 2>@ stderr} result]} {
  puts "ERROR: xsim failed: $result"
  cd $old_dir
  exit 1
}

set sim_log [file join $build_root simulate.log]
if {![file exists $sim_log]} {
  puts "ERROR: simulation log was not generated"
  cd $old_dir
  exit 1
}
set fh [open $sim_log r]
set sim_text [read $fh]
close $fh
if {[string first "PASS: Hestia U200 DDR stress sustained $stress_max_packets packets" $sim_text] < 0 ||
    [string first "Fatal:" $sim_text] >= 0} {
  puts "ERROR: U200 DDR stress simulation did not reach a clean PASS marker"
  cd $old_dir
  exit 1
}

cd $old_dir
exit 0
