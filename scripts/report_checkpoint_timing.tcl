if {[llength $argv] < 1} {
  puts "ERROR: usage: vivado -mode batch -source report_checkpoint_timing.tcl -tclargs <checkpoint.dcp> ?out_dir?"
  exit 1
}

set dcp_file [file normalize [lindex $argv 0]]
if {![file exists $dcp_file]} {
  puts "ERROR: checkpoint not found: $dcp_file"
  exit 1
}

if {[llength $argv] > 1} {
  set out_dir [file normalize [lindex $argv 1]]
} else {
  set out_dir [file dirname $dcp_file]
}
file mkdir $out_dir

open_checkpoint $dcp_file

set stem [file rootname [file tail $dcp_file]]
report_timing_summary -max_paths 20 \
  -file [file join $out_dir ${stem}_timing_summary.rpt]
report_timing -delay_type max -sort_by group -max_paths 20 -nworst 1 \
  -file [file join $out_dir ${stem}_worst_paths.rpt]
report_utilization -hierarchical \
  -file [file join $out_dir ${stem}_utilization_hier.rpt]
report_utilization \
  -file [file join $out_dir ${stem}_utilization.rpt]

puts "Timing summary: [file join $out_dir ${stem}_timing_summary.rpt]"
puts "Worst paths:    [file join $out_dir ${stem}_worst_paths.rpt]"
puts "Utilization:    [file join $out_dir ${stem}_utilization.rpt]"
exit 0
