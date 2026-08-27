if {[llength $argv] < 1} {
  puts "ERROR: usage: vivado -mode batch -source check_u200_cdc_falsepath.tcl -tclargs <routed_checkpoint.dcp> ?out_dir?"
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

set calib_meta_pins [get_pins -hierarchical -filter {NAME =~ *calib_done_meta_reg/D}]
puts "CALIB_DONE_META_PINS=[llength $calib_meta_pins] $calib_meta_pins"
if {[llength $calib_meta_pins] == 0} {
  puts "ERROR: no calib_done_meta_reg/D pin matched"
  exit 2
}

set_false_path -to $calib_meta_pins

report_timing_summary -max_paths 20 \
  -file [file join $out_dir u200_cdc_falsepath_timing_summary.rpt]
report_timing -delay_type max -sort_by group -max_paths 20 -nworst 1 \
  -file [file join $out_dir u200_cdc_falsepath_worst_paths.rpt]

puts "Timing summary: [file join $out_dir u200_cdc_falsepath_timing_summary.rpt]"
puts "Worst paths:    [file join $out_dir u200_cdc_falsepath_worst_paths.rpt]"
exit 0
