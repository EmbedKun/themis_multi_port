set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]

proc hestia_env_or {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

set policy_mode [hestia_env_or HESTIA_BASELINE_DDR_POLICY_MODE 0]
set policy_alpha_shift [hestia_env_or HESTIA_BASELINE_DDR_POLICY_ALPHA_SHIFT 0]
set max_packets [hestia_env_or HESTIA_BASELINE_DDR_MAX_PACKETS 96]

if {[llength $argv] > 0} {
  set build_root [file normalize [lindex $argv 0]]
} elseif {[info exists ::env(HESTIA_BASELINE_DDR_SIM_ROOT)] && $::env(HESTIA_BASELINE_DDR_SIM_ROOT) ne ""} {
  set build_root [file normalize $::env(HESTIA_BASELINE_DDR_SIM_ROOT)]
} else {
  set build_root [file join $repo_dir build baseline_ddr_policy_${policy_mode}_sim]
}
file mkdir $build_root

set rtl_files [list \
  [file join $repo_dir rtl hestia_pkg.sv] \
  [file join $repo_dir rtl hestia_port_bbq.sv] \
  [file join $repo_dir rtl hestia_policy_dt.sv] \
  [file join $repo_dir rtl hestia_policy_occamy.sv] \
  [file join $repo_dir rtl hestia_policy_obm.sv] \
  [file join $repo_dir rtl hestia_core_ddr_bbq.sv] \
]
set sim_files [list \
  [file join $repo_dir sim axi_mem_model.sv] \
  [file join $repo_dir sim tb_hestia_baseline_ddr.sv] \
]
set glbl_file [file join $::env(XILINX_VIVADO) data verilog src glbl.v]

set xvlog_defs [list \
  -d BASELINE_DDR_POLICY_MODE=$policy_mode \
  -d BASELINE_DDR_POLICY_ALPHA_SHIFT=$policy_alpha_shift \
  -d BASELINE_DDR_MAX_PACKETS=$max_packets \
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

set xelab_cmd [list xelab --debug off --relax --mt 8 -L work -L unisims_ver -L unimacro_ver -L secureip -s tb_hestia_baseline_ddr_behav work.tb_hestia_baseline_ddr work.glbl]
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

set xsim_cmd [list xsim tb_hestia_baseline_ddr_behav -wdb /dev/null -tclbatch [file join $build_root xsim_run.tcl] -log simulate.log]
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
set marker "PASS: DDR-aware shared-buffer baseline policy=${policy_mode} preserves per-port rank order"
if {[string first $marker $sim_text] < 0 || [string first "Fatal:" $sim_text] >= 0} {
  puts "ERROR: DDR baseline simulation did not reach a clean PASS marker"
  puts $sim_text
  cd $old_dir
  exit 1
}

puts "DDR baseline simulation PASS policy=${policy_mode}"
cd $old_dir
exit 0
