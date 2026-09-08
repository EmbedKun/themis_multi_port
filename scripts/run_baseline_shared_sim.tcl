set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
if {[llength $argv] > 0} {
  set build_root [file normalize [lindex $argv 0]]
} elseif {[info exists ::env(HESTIA_BASELINE_SIM_ROOT)] && $::env(HESTIA_BASELINE_SIM_ROOT) ne ""} {
  set build_root [file normalize $::env(HESTIA_BASELINE_SIM_ROOT)]
} else {
  set build_root [file join $repo_dir build hestia_baseline_shared_sim]
}
file mkdir $build_root

set rtl_files [list \
  [file join $repo_dir rtl hestia_pkg.sv] \
  [file join $repo_dir rtl hestia_port_bbq.sv] \
  [file join $repo_dir rtl hestia_policy_dt.sv] \
  [file join $repo_dir rtl hestia_policy_occamy.sv] \
  [file join $repo_dir rtl hestia_policy_obm.sv] \
  [file join $repo_dir rtl hestia_baseline_shared_core.sv] \
]
set sim_file [file join $repo_dir sim tb_hestia_baseline_shared.sv]
set glbl_file [file join $::env(XILINX_VIVADO) data verilog src glbl.v]
set old_dir [pwd]

proc run_policy_case {repo_dir build_root rtl_files sim_file glbl_file policy} {
  set case_root [file join $build_root policy_$policy]
  file mkdir $case_root
  cd $case_root
  file delete -force xsim.dir xvlog.log xelab.log simulate.log webtalk.log

  set xvlog_sv_cmd [concat [list xvlog --sv --relax -d BASELINE_POLICY_MODE=$policy] $rtl_files [list $sim_file]]
  puts "Running: $xvlog_sv_cmd"
  if {[catch {exec {*}$xvlog_sv_cmd >@ stdout 2>@ stderr} result]} {
    puts "ERROR: xvlog SystemVerilog compile failed for policy $policy: $result"
    return 1
  }

  set xvlog_glbl_cmd [list xvlog --relax $glbl_file]
  puts "Running: $xvlog_glbl_cmd"
  if {[catch {exec {*}$xvlog_glbl_cmd >@ stdout 2>@ stderr} result]} {
    puts "ERROR: xvlog glbl compile failed for policy $policy: $result"
    return 1
  }

  set snap "tb_hestia_baseline_shared_policy_${policy}_behav"
  set xelab_cmd [list xelab --debug off --relax --mt 8 -L work -L unisims_ver -L unimacro_ver -L secureip -s $snap work.tb_hestia_baseline_shared work.glbl]
  puts "Running: $xelab_cmd"
  if {[catch {exec {*}$xelab_cmd >@ stdout 2>@ stderr} result]} {
    puts "ERROR: xelab failed for policy $policy: $result"
    return 1
  }

  set run_fh [open [file join $case_root xsim_run.tcl] w]
  puts $run_fh "run -all"
  puts $run_fh "quit"
  close $run_fh

  set xsim_cmd [list xsim $snap -wdb /dev/null -tclbatch [file join $case_root xsim_run.tcl] -log simulate.log]
  puts "Running: $xsim_cmd"
  if {[catch {exec {*}$xsim_cmd >@ stdout 2>@ stderr} result]} {
    puts "ERROR: xsim failed for policy $policy: $result"
    return 1
  }

  set sim_log [file join $case_root simulate.log]
  set fh [open $sim_log r]
  set sim_text [read $fh]
  close $fh
  if {[string first "PASS: Hestia baseline shared-buffer regression policy=$policy" $sim_text] < 0 ||
      [string first "Fatal:" $sim_text] >= 0} {
    puts "ERROR: baseline simulation did not reach a clean PASS marker for policy $policy"
    return 1
  }
  return 0
}

cd $build_root
foreach policy {0 1 2 3} {
  cd $old_dir
  set rc [run_policy_case $repo_dir $build_root $rtl_files $sim_file $glbl_file $policy]
  if {$rc != 0} {
    cd $old_dir
    exit 1
  }
}

cd $old_dir
exit 0
