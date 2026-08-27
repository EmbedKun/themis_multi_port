set build_root ""
if {[llength $argv] > 0 && [lindex $argv 0] ne ""} {
  set build_root [file normalize [lindex $argv 0]]
} elseif {[info exists ::env(HESTIA_BUILD_ROOT)] && $::env(HESTIA_BUILD_ROOT) ne ""} {
  set build_root [file normalize $::env(HESTIA_BUILD_ROOT)]
} else {
  puts "ERROR: pass build_root as argv[0] or set HESTIA_BUILD_ROOT"
  exit 1
}

set project_name hestia_u200_ddr
set build_dir [file join $build_root vivado]
set xpr_file [file join $build_dir ${project_name}.xpr]
if {![file exists $xpr_file]} {
  puts "ERROR: missing project: $xpr_file"
  exit 1
}

open_project $xpr_file

set jobs 1
if {[info exists ::env(HESTIA_VIVADO_JOBS)] && $::env(HESTIA_VIVADO_JOBS) ne ""} {
  set jobs $::env(HESTIA_VIVADO_JOBS)
}

foreach run_name [list impl_1 synth_1 hestia_u200_bd_mp_top_0_synth_1] {
  set runs [get_runs -quiet $run_name]
  if {[llength $runs] > 0} {
    puts "Resetting run: $run_name"
    reset_run $run_name
  }
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

open_run impl_1
set impl_dir [file join $build_dir ${project_name}.runs impl_1]
report_utilization -file [file join $impl_dir hestia_u200_utilization_impl.rpt]
report_timing_summary -file [file join $impl_dir hestia_u200_timing_summary_impl.rpt]
report_route_status -file [file join $impl_dir hestia_u200_route_status_impl.rpt]

set bitfiles [glob -nocomplain [file join $impl_dir *.bit]]
set ltxfiles [glob -nocomplain [file join $impl_dir *.ltx]]
if {[llength $bitfiles] > 0} {
  puts "Hestia U200 bitstream: [lindex $bitfiles 0]"
}
if {[llength $ltxfiles] > 0} {
  puts "Hestia U200 probes: [lindex $ltxfiles 0]"
}
exit 0
