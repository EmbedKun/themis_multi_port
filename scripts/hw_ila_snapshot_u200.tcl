set build_root [expr {[info exists ::env(HESTIA_BUILD_ROOT)] && $::env(HESTIA_BUILD_ROOT) ne "" ? [file normalize $::env(HESTIA_BUILD_ROOT)] : ""}]
if {$build_root eq ""} {
  puts "ERROR: HESTIA_BUILD_ROOT is required"
  exit 1
}

set bit_file [expr {[info exists ::env(HESTIA_BIT_FILE)] && $::env(HESTIA_BIT_FILE) ne "" ? [file normalize $::env(HESTIA_BIT_FILE)] : [file join $build_root vivado hestia_u200_ddr.runs impl_1 hestia_u200_bd_wrapper.bit]}]
set default_ltx_file [file join $build_root vivado hestia_u200_ddr.runs impl_1 hestia_u200_bd_wrapper.ltx]
if {![file exists $default_ltx_file]} {
  set default_ltx_file [file join $build_root vivado hestia_u200_ddr.runs impl_1 debug_nets.ltx]
}
set ltx_file [expr {[info exists ::env(HESTIA_LTX_FILE)] && $::env(HESTIA_LTX_FILE) ne "" ? [file normalize $::env(HESTIA_LTX_FILE)] : $default_ltx_file}]
set csv_file [expr {[info exists ::env(HESTIA_ILA_CSV)] && $::env(HESTIA_ILA_CSV) ne "" ? [file normalize $::env(HESTIA_ILA_CSV)] : [file join $build_root hw_ila_snapshot.csv]}]
set wdb_file [expr {[info exists ::env(HESTIA_ILA_WDB)] && $::env(HESTIA_ILA_WDB) ne "" ? [file normalize $::env(HESTIA_ILA_WDB)] : [file join $build_root hw_ila_snapshot.wdb]}]
set server_url [expr {[info exists ::env(HESTIA_HW_SERVER)] && $::env(HESTIA_HW_SERVER) ne "" ? $::env(HESTIA_HW_SERVER) : "localhost:3121"}]
set do_program [expr {[info exists ::env(HESTIA_PROGRAM)] && $::env(HESTIA_PROGRAM) ne "" ? $::env(HESTIA_PROGRAM) : 0}]
set trigger_name [expr {[info exists ::env(HESTIA_ILA_TRIGGER)] && $::env(HESTIA_ILA_TRIGGER) ne "" ? $::env(HESTIA_ILA_TRIGGER) : "calib"}]

if {![file exists $bit_file]} {
  puts "ERROR: bitstream not found: $bit_file"
  exit 1
}
if {![file exists $ltx_file]} {
  puts "ERROR: probes file not found: $ltx_file"
  exit 1
}

open_hw_manager
connect_hw_server -url $server_url

set targets [get_hw_targets *]
puts "Hestia HW targets: $targets"
if {[llength $targets] == 0} {
  puts "ERROR: no hardware targets"
  exit 1
}
current_hw_target [lindex $targets 0]
open_hw_target

set devices [get_hw_devices *]
puts "Hestia HW devices: $devices"
if {[llength $devices] == 0} {
  puts "ERROR: no hardware devices"
  exit 1
}

set dev [lindex $devices 0]
current_hw_device $dev
set_property PROBES.FILE $ltx_file $dev
if {$do_program} {
  set_property PROGRAM.FILE $bit_file $dev
  puts "Hestia programming device $dev"
  program_hw_devices $dev
}
refresh_hw_device $dev

set ilas [get_hw_ilas *]
puts "Hestia ILAs: $ilas"
if {[llength $ilas] == 0} {
  puts "ERROR: no ILA cores found"
  exit 1
}
set ila [lindex $ilas 0]

set trigger_probe ""
if {$trigger_name eq "done"} {
  foreach probe [get_hw_probes *mp_top_done -of_objects $ila] {
    set trigger_probe $probe
    break
  }
} elseif {$trigger_name eq "calib"} {
  foreach probe [get_hw_probes *calib_done_sync_dbg -of_objects $ila] {
    set trigger_probe $probe
    break
  }
}
if {$trigger_probe eq ""} {
  foreach probe [get_hw_probes *probe4* -of_objects $ila] {
    set trigger_probe $probe
    break
  }
}
if {$trigger_probe eq ""} {
  foreach probe [get_hw_probes * -of_objects $ila] {
    set trigger_probe $probe
    break
  }
}
if {$trigger_probe eq ""} {
  puts "ERROR: no trigger probe found"
  exit 1
}

set_property TRIGGER_COMPARE_VALUE "eq1'b1" $trigger_probe
catch {set_property CONTROL.TRIGGER_POSITION 512 $ila}
puts "Hestia ILA probe: $trigger_probe"
puts "Hestia ILA trigger: $trigger_name == 1"

run_hw_ila $ila
wait_on_hw_ila $ila
if {[catch {get_property STATUS $ila} ila_status]} {
  set ila_status "completed"
}
puts "Hestia ILA status: $ila_status"

set data [upload_hw_ila_data $ila]
write_hw_ila_data -force -csv_file $csv_file $data
write_hw_ila_data -force $wdb_file $data
puts "Hestia ILA CSV: $csv_file"
puts "Hestia ILA WDB: $wdb_file"
puts "Light probe0 low bits: [31:0]=generated [63:32]=dequeued [95:64]=sram_dequeue [127:96]=direct_ddr_dequeue [159:128]=rank_errors."
exit 0
