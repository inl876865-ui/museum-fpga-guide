# This is default flow script for normal condition: neither syn ip flow nor multi-seed mode.
# Noted that only script in editable zone can be changed. 

if { ![info exists alRun] } { source ./settings.cfg }
proc step_begin { step } {
  set stopFile ".stop.f"
  if {[file isfile .stop.f]} {
    puts ""
    puts " #Halting run"
    puts ""
    return -code error
  }
  set beginFile ".$step.begin.f"
  set platform "$::tcl_platform(platform)"
  set user "$::tcl_platform(user)"
  set pid [pid]
  set host ""
  if { [string equal $platform unix] } {
    if { [info exists ::env(HOSTNAME)] } {
      set host $::env(HOSTNAME)
    }
  } else {
    if { [info exists ::env(COMPUTERNAME)] } {
      set host $::env(COMPUTERNAME)
    }
  }
  set ch [open $beginFile w]
  puts $ch "<?xml version=\"1.0\"?>"
  puts $ch "<ProcessHandle Version=\"1\" Minor=\"0\">"
  puts $ch "    <Process Ownner=\"$user\" Host=\"$host\" Pid=\"$pid\">"
  puts $ch "    </Process>"
  puts $ch "</ProcessHandle>"
  close $ch
}
proc step_end { step } {
  set endFile ".$step.end.f"
  set ch [open $endFile w]
  close $ch
}
proc step_error { step } {
  set errorFile ".$step.error.f"
  set ch [open $errorFile w]
  close $ch
}
set stepList {read_design opt_rtl opt_gate opt_place opt_route bitgen}
set l [lsearch $stepList $start_step]
set r [lsearch $stepList $end_step]
proc prepare { step } {
  upvar device_name device_name
  upvar package_name package_name
  upvar speed speed
  upvar prj_name prj_name
  upvar parent parent
  upvar synWildParams synWildParams
  upvar phyWildParams phyWildParams
  upvar alRun alRun
  upvar singleRun singleRun
  upvar sp sp
  upvar ADCList ADCList
  upvar SDCList SDCList
  set command "import_device $device_name -package $package_name"; if { [info exists speed] } { append command " -speed ${speed}" }; eval $command
  if { ![info exists singleRun] } {
    if { [info exists alRun] } { 
        open_project ${prj_name}.al -single_run
        load_run_param -run ${alRun}
    } else {
    set command "open_project {${prj_name}.prj}"; if { $step != 0 } { append command " -noanalyze" }; eval $command
    }
  }
  set preSteps {non elaborate rtl gate place pr}
  set preStep [ lindex ${preSteps} $step ]
  if { $step == 3 } { import_db $parent/${prj_name}_${preStep}.db }\
  elseif { $step != 0 } { import_db ${prj_name}_${preStep}.db }
  set wildParams ""
  if { [info exists synWildParams] } { set wildParams ${synWildParams} } elseif { [info exists phyWildParams] } { set wildParams ${phyWildParams} }
  for { set i 0 } { $i < [llength $wildParams] } { incr i 3 } {
    set_param [lindex $wildParams $i] [lindex $wildParams [expr $i + 1]] [lindex $wildParams [expr $i + 2]]
  }
  if { [info exists singleRun] } report_param
  if { [info exists sp] } {
    if { [info exists ADCList] } { foreach adc $ADCList { read_adc $adc } }
    if { [info exists SDCList] } {
      clear_sdc -user
      foreach sdc $SDCList { read_sdc $sdc }
    }
  }
}
proc read_design_fun {} {
  upvar prj_name prj_name
  upvar top_model_name top_model_name
  upvar singleRun singleRun
  upvar ADCList ADCList
  upvar IpADCList IpADCList
  upvar SDCList SDCList
  upvar IpSDCList IpSDCList
  if { ![info exists singleRun] } { commit_param -step design }

### Editable zone for read_design ###
  set_param rtl min_control_set 2
  set_param rtl min_ripple_len 24
  elaborate -top $top_model_name

#####################################
  if { [info exists ADCList] } { foreach adc $ADCList { read_adc $adc } }
  if { [info exists IpADCList] } {
    set i 0
    while {$i < [llength $IpADCList]} {
      read_ip_adc -ip [lindex $IpADCList $i] -file [lindex $IpADCList [expr $i + 1] ]
      incr i 2
    }
  }
  if { [info exists SDCList] } { foreach sdc $SDCList { read_sdc $sdc } }
  if { [info exists IpSDCList] } {
    set i 0
    while {$i < [llength $IpSDCList]} {
      read_sdc -ip [lindex $IpSDCList $i] [lindex $IpSDCList [expr $i + 1] ]
      incr i 2
    }
  }
  export_db ${prj_name}_elaborate.db
}
proc opt_rtl_fun {} {
  upvar prj_name prj_name
  upvar singleRun singleRun
  if { ![info exists singleRun] } { commit_param -step rtl }


### Editable zone for opt_rtl ###
  upvar chipDebugger chipDebugger
  if { ![info exists chipDebugger] } {
     insert_debugger
  } else { insert_debugger $chipDebugger }
  optimize_rtl
  report_area -file ${prj_name}_rtl.area
#################################

  export_db ${prj_name}_rtl.db
}
proc opt_gate_fun {} {
  upvar prj_name prj_name
  upvar area_option area_option
  upvar singleRun singleRun
  if { ![info exists singleRun] } { commit_param -step gate }

### Editable zone for opt_gate ###
  set_param gate pack_effort high
  set_param gate pack_seq_in_io off
  set_param gate opt_area high
  set_param gate map_mode area_prior
  set_param gate map_strategy 3
  optimize_gate ${area_option} ${prj_name}_gate.area
  legalize_phy_inst
  read_sdc ../../../user_source/constraints_source/scaler_clock_bridge.sdc
  update_timing
  report_timing_status -file ${prj_name}_gate.ts
  report_timing_summary -file ${prj_name}_gate.timing
  flow_status -file flow.status

##################################

  export_db ${prj_name}_gate.db
}
proc opt_place_fun {} {
  upvar prj_name prj_name
  upvar cwcList cwcList
  upvar singleRun singleRun
  upvar chipDebugger chipDebugger
  upvar bkaADCList bkaADCList
  upvar arr_filter arr_filter
  upvar arr_pwns arr_pwns
  upvar arr_cong arr_cong
  if { ![info exists singleRun] } { commit_param -step place }
  if { ![info exists chipDebugger] } {
     insert_debugger
  } else { insert_debugger $chipDebugger }
  if { [info exists bkaADCList] } { 
     clear_inst_adc
     foreach adc $bkaADCList { read_adc $adc } 
  }

### Editable zone for opt_place ###
set_param place pr_strategy 2
set_param place macro_performance macro_congestion
set_param place seed 53

set_param place pack_mode lower_pin_density

set_param place hfn_opt_effort high
set_param place effort high

set_param place opt_timing ultra

set_param place post_place_opt ultra

set_param route effort routability

set_param route timing greedy

set_param route post_route_opt ultra

if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[8]}]] != 1} {error "Expected exactly one current SDRAM bit8 register"}
create_bound sdram_dq8_near_input -mode fixed -width 3 -height 9 -origin {37 40}
add_cells_to_bound -bound sdram_dq8_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[8]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[9]}]] != 1} {error "Expected exactly one current SDRAM bit9 register"}
create_bound sdram_dq9_near_input -mode fixed -width 3 -height 9 -origin {37 40}
add_cells_to_bound -bound sdram_dq9_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[9]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[10]}]] != 1} {error "Expected exactly one current SDRAM bit10 register"}
create_bound sdram_dq10_near_input -mode fixed -width 3 -height 9 -origin {37 43}
add_cells_to_bound -bound sdram_dq10_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[10]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[11]}]] != 1} {error "Expected exactly one current SDRAM bit11 register"}
create_bound sdram_dq11_near_input -mode fixed -width 3 -height 9 -origin {37 43}
add_cells_to_bound -bound sdram_dq11_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[11]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[12]}]] != 1} {error "Expected exactly one current SDRAM bit12 register"}
create_bound sdram_dq12_near_input -mode fixed -width 3 -height 9 -origin {37 46}
add_cells_to_bound -bound sdram_dq12_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[12]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[13]}]] != 1} {error "Expected exactly one current SDRAM bit13 register"}
create_bound sdram_dq13_near_input -mode fixed -width 3 -height 9 -origin {37 46}
add_cells_to_bound -bound sdram_dq13_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[13]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[14]}]] != 1} {error "Expected exactly one current SDRAM bit14 register"}
create_bound sdram_dq14_near_input -mode fixed -width 3 -height 9 -origin {37 52}
add_cells_to_bound -bound sdram_dq14_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[14]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[15]}]] != 1} {error "Expected exactly one current SDRAM bit15 register"}
create_bound sdram_dq15_near_input -mode fixed -width 3 -height 9 -origin {37 52}
add_cells_to_bound -bound sdram_dq15_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[15]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[16]}]] != 1} {error "Expected exactly one current SDRAM bit16 register"}
create_bound sdram_dq16_near_input -mode fixed -width 3 -height 9 -origin {1 1}
add_cells_to_bound -bound sdram_dq16_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[16]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[17]}]] != 1} {error "Expected exactly one current SDRAM bit17 register"}
create_bound sdram_dq17_near_input -mode fixed -width 3 -height 9 -origin {1 1}
add_cells_to_bound -bound sdram_dq17_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[17]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[18]}]] != 1} {error "Expected exactly one current SDRAM bit18 register"}
create_bound sdram_dq18_near_input -mode fixed -width 3 -height 9 -origin {1 4}
add_cells_to_bound -bound sdram_dq18_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[18]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[19]}]] != 1} {error "Expected exactly one current SDRAM bit19 register"}
create_bound sdram_dq19_near_input -mode fixed -width 3 -height 9 -origin {1 4}
add_cells_to_bound -bound sdram_dq19_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[19]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[20]}]] != 1} {error "Expected exactly one current SDRAM bit20 register"}
create_bound sdram_dq20_near_input -mode fixed -width 3 -height 9 -origin {1 10}
add_cells_to_bound -bound sdram_dq20_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[20]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[21]}]] != 1} {error "Expected exactly one current SDRAM bit21 register"}
create_bound sdram_dq21_near_input -mode fixed -width 3 -height 9 -origin {1 10}
add_cells_to_bound -bound sdram_dq21_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[21]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[22]}]] != 1} {error "Expected exactly one current SDRAM bit22 register"}
create_bound sdram_dq22_near_input -mode fixed -width 3 -height 9 -origin {1 13}
add_cells_to_bound -bound sdram_dq22_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[22]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[23]}]] != 1} {error "Expected exactly one current SDRAM bit23 register"}
create_bound sdram_dq23_near_input -mode fixed -width 3 -height 9 -origin {1 16}
add_cells_to_bound -bound sdram_dq23_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[23]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[24]}]] != 1} {error "Expected exactly one current SDRAM bit24 register"}
create_bound sdram_dq24_near_input -mode fixed -width 3 -height 9 -origin {37 16}
add_cells_to_bound -bound sdram_dq24_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[24]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[25]}]] != 1} {error "Expected exactly one current SDRAM bit25 register"}
create_bound sdram_dq25_near_input -mode fixed -width 3 -height 9 -origin {37 16}
add_cells_to_bound -bound sdram_dq25_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[25]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[26]}]] != 1} {error "Expected exactly one current SDRAM bit26 register"}
create_bound sdram_dq26_near_input -mode fixed -width 3 -height 9 -origin {37 10}
add_cells_to_bound -bound sdram_dq26_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[26]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[27]}]] != 1} {error "Expected exactly one current SDRAM bit27 register"}
create_bound sdram_dq27_near_input -mode fixed -width 3 -height 9 -origin {37 7}
add_cells_to_bound -bound sdram_dq27_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[27]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[28]}]] != 1} {error "Expected exactly one current SDRAM bit28 register"}
create_bound sdram_dq28_near_input -mode fixed -width 3 -height 9 -origin {37 4}
add_cells_to_bound -bound sdram_dq28_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[28]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[29]}]] != 1} {error "Expected exactly one current SDRAM bit29 register"}
create_bound sdram_dq29_near_input -mode fixed -width 3 -height 9 -origin {37 4}
add_cells_to_bound -bound sdram_dq29_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[29]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[30]}]] != 1} {error "Expected exactly one current SDRAM bit30 register"}
create_bound sdram_dq30_near_input -mode fixed -width 3 -height 9 -origin {37 1}
add_cells_to_bound -bound sdram_dq30_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[30]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[31]}]] != 1} {error "Expected exactly one current SDRAM bit31 register"}
create_bound sdram_dq31_near_input -mode fixed -width 3 -height 9 -origin {37 1}
add_cells_to_bound -bound sdram_dq31_near_input -cells {U3/u2_ram/u2_wrrd/Sdr_rd_dout_reg[31]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[0]}]] != 1} {error "Exactly one writeDQ0 register required"}
create_bound sdram_write_dq0_near_PAD -mode fixed -width 3 -height 9 -origin {1 55}
add_cells_to_bound -bound sdram_write_dq0_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[0]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[1]}]] != 1} {error "Exactly one writeDQ1 register required"}
create_bound sdram_write_dq1_near_PAD -mode fixed -width 3 -height 9 -origin {1 55}
add_cells_to_bound -bound sdram_write_dq1_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[1]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[2]}]] != 1} {error "Exactly one writeDQ2 register required"}
create_bound sdram_write_dq2_near_PAD -mode fixed -width 3 -height 9 -origin {1 52}
add_cells_to_bound -bound sdram_write_dq2_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[2]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[3]}]] != 1} {error "Exactly one writeDQ3 register required"}
create_bound sdram_write_dq3_near_PAD -mode fixed -width 3 -height 9 -origin {1 52}
add_cells_to_bound -bound sdram_write_dq3_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[3]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[4]}]] != 1} {error "Exactly one writeDQ4 register required"}
create_bound sdram_write_dq4_near_PAD -mode fixed -width 3 -height 9 -origin {1 49}
add_cells_to_bound -bound sdram_write_dq4_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[4]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[5]}]] != 1} {error "Exactly one writeDQ5 register required"}
create_bound sdram_write_dq5_near_PAD -mode fixed -width 3 -height 9 -origin {1 49}
add_cells_to_bound -bound sdram_write_dq5_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[5]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[6]}]] != 1} {error "Exactly one writeDQ6 register required"}
create_bound sdram_write_dq6_near_PAD -mode fixed -width 3 -height 9 -origin {1 46}
add_cells_to_bound -bound sdram_write_dq6_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[6]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[7]}]] != 1} {error "Exactly one writeDQ7 register required"}
create_bound sdram_write_dq7_near_PAD -mode fixed -width 3 -height 9 -origin {1 46}
add_cells_to_bound -bound sdram_write_dq7_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[7]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[8]}]] != 1} {error "Exactly one writeDQ8 register required"}
create_bound sdram_write_dq8_near_PAD -mode fixed -width 3 -height 9 -origin {37 40}
add_cells_to_bound -bound sdram_write_dq8_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[8]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[9]}]] != 1} {error "Exactly one writeDQ9 register required"}
create_bound sdram_write_dq9_near_PAD -mode fixed -width 3 -height 9 -origin {37 40}
add_cells_to_bound -bound sdram_write_dq9_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[9]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[10]}]] != 1} {error "Exactly one writeDQ10 register required"}
create_bound sdram_write_dq10_near_PAD -mode fixed -width 3 -height 9 -origin {37 43}
add_cells_to_bound -bound sdram_write_dq10_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[10]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[11]}]] != 1} {error "Exactly one writeDQ11 register required"}
create_bound sdram_write_dq11_near_PAD -mode fixed -width 3 -height 9 -origin {37 43}
add_cells_to_bound -bound sdram_write_dq11_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[11]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[12]}]] != 1} {error "Exactly one writeDQ12 register required"}
create_bound sdram_write_dq12_near_PAD -mode fixed -width 3 -height 9 -origin {37 46}
add_cells_to_bound -bound sdram_write_dq12_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[12]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[13]}]] != 1} {error "Exactly one writeDQ13 register required"}
create_bound sdram_write_dq13_near_PAD -mode fixed -width 3 -height 9 -origin {37 46}
add_cells_to_bound -bound sdram_write_dq13_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[13]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[14]}]] != 1} {error "Exactly one writeDQ14 register required"}
create_bound sdram_write_dq14_near_PAD -mode fixed -width 3 -height 9 -origin {37 52}
add_cells_to_bound -bound sdram_write_dq14_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[14]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[15]}]] != 1} {error "Exactly one writeDQ15 register required"}
create_bound sdram_write_dq15_near_PAD -mode fixed -width 3 -height 9 -origin {37 52}
add_cells_to_bound -bound sdram_write_dq15_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[15]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[16]}]] != 1} {error "Exactly one writeDQ16 register required"}
create_bound sdram_write_dq16_near_PAD -mode fixed -width 3 -height 9 -origin {1 1}
add_cells_to_bound -bound sdram_write_dq16_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[16]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[17]}]] != 1} {error "Exactly one writeDQ17 register required"}
create_bound sdram_write_dq17_near_PAD -mode fixed -width 3 -height 9 -origin {1 1}
add_cells_to_bound -bound sdram_write_dq17_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[17]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[18]}]] != 1} {error "Exactly one writeDQ18 register required"}
create_bound sdram_write_dq18_near_PAD -mode fixed -width 3 -height 9 -origin {1 4}
add_cells_to_bound -bound sdram_write_dq18_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[18]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[19]}]] != 1} {error "Exactly one writeDQ19 register required"}
create_bound sdram_write_dq19_near_PAD -mode fixed -width 3 -height 9 -origin {1 4}
add_cells_to_bound -bound sdram_write_dq19_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[19]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[20]}]] != 1} {error "Exactly one writeDQ20 register required"}
create_bound sdram_write_dq20_near_PAD -mode fixed -width 3 -height 9 -origin {1 10}
add_cells_to_bound -bound sdram_write_dq20_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[20]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[21]}]] != 1} {error "Exactly one writeDQ21 register required"}
create_bound sdram_write_dq21_near_PAD -mode fixed -width 3 -height 9 -origin {1 10}
add_cells_to_bound -bound sdram_write_dq21_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[21]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[22]}]] != 1} {error "Exactly one writeDQ22 register required"}
create_bound sdram_write_dq22_near_PAD -mode fixed -width 3 -height 9 -origin {1 13}
add_cells_to_bound -bound sdram_write_dq22_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[22]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[23]}]] != 1} {error "Exactly one writeDQ23 register required"}
create_bound sdram_write_dq23_near_PAD -mode fixed -width 3 -height 9 -origin {1 16}
add_cells_to_bound -bound sdram_write_dq23_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[23]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[24]}]] != 1} {error "Exactly one writeDQ24 register required"}
create_bound sdram_write_dq24_near_PAD -mode fixed -width 3 -height 9 -origin {37 16}
add_cells_to_bound -bound sdram_write_dq24_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[24]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[25]}]] != 1} {error "Exactly one writeDQ25 register required"}
create_bound sdram_write_dq25_near_PAD -mode fixed -width 3 -height 9 -origin {37 16}
add_cells_to_bound -bound sdram_write_dq25_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[25]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[26]}]] != 1} {error "Exactly one writeDQ26 register required"}
create_bound sdram_write_dq26_near_PAD -mode fixed -width 3 -height 9 -origin {37 10}
add_cells_to_bound -bound sdram_write_dq26_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[26]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[27]}]] != 1} {error "Exactly one writeDQ27 register required"}
create_bound sdram_write_dq27_near_PAD -mode fixed -width 3 -height 9 -origin {37 7}
add_cells_to_bound -bound sdram_write_dq27_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[27]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[28]}]] != 1} {error "Exactly one writeDQ28 register required"}
create_bound sdram_write_dq28_near_PAD -mode fixed -width 3 -height 9 -origin {37 4}
add_cells_to_bound -bound sdram_write_dq28_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[28]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[29]}]] != 1} {error "Exactly one writeDQ29 register required"}
create_bound sdram_write_dq29_near_PAD -mode fixed -width 3 -height 9 -origin {37 4}
add_cells_to_bound -bound sdram_write_dq29_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[29]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[30]}]] != 1} {error "Exactly one writeDQ30 register required"}
create_bound sdram_write_dq30_near_PAD -mode fixed -width 3 -height 9 -origin {37 1}
add_cells_to_bound -bound sdram_write_dq30_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[30]}
if {[llength [get_cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[31]}]] != 1} {error "Exactly one writeDQ31 register required"}
create_bound sdram_write_dq31_near_PAD -mode fixed -width 3 -height 9 -origin {37 1}
add_cells_to_bound -bound sdram_write_dq31_near_PAD -cells {U3/u2_ram/u2_wrrd/app_wr_din_7d_reg[31]}
# TD official CongestionHigh; no source or SDC changes.
set_param place opt_timing high
set_param place ofv 70
set_param place opt_max_density 50
set_param place target_density 0.6
set_param place target_density_pp 0.7
set_param place aggressive_opt 20
set_param place enhanced_beeline_opt 2
set_param place enhanced_gp on
set_param place non_crit_opt on
set_param place post_place_opt high
set_param place enable_congestion_recovery on
set_param route post_route_opt high
source [file normalize ../../flow/preflight_cluster_soft.tcl]
  place
  update_timing -mode manhattan
  report_timing_summary -file ${prj_name}_place.timing
  report_area -io_info -file ${prj_name}_phy.area
  flow_status -file place_flow.status
  report_clock_utilization -file place_clock_utilization.txt
  if { [string equal $arr_filter true] } { flow_continue_check -step place -wns $arr_pwns -congestion $arr_cong }
###################################

  export_db ${prj_name}_place.db
}
proc opt_route_fun {} {
  upvar prj_name prj_name
  upvar singleRun singleRun
  upvar arr_filter arr_filter
  upvar arr_rwns arr_rwns
  upvar drHoldFix drHoldFix
  if { ![info exists singleRun] } { commit_param -step route }

### Editable zone for opt_route ###
  set_param route effort routability
  set_param route timing normal
  set_param route post_route_opt ultra
  route
  fix_hold -clock_opt -eco
  route -eco
  drc_check -all -place -route -verbose
  report_area -io_info -file ${prj_name}_phy.area
  update_timing -mode final
  report_timing_status -file ${prj_name}_phy.ts
  report_timing_summary -file ${prj_name}_pr.timing
  report_timing_summary -file final_timing.rpt
  report_timing -file ${prj_name}_paths.rpt
  report_timing_exception -file ${prj_name}_exception.timing
  flow_status -file route_flow.status
  report_clock_utilization -file route_clock_utilization.txt

###################################

  export_db ${prj_name}_pr.db
}
proc bitgen_fun {} {
  upvar prj_name prj_name
  upvar cpcList cpcList
  upvar singleRun singleRun
  if { ![info exists singleRun] } { commit_param -step bitgen }
  if { [info exists cpcList] } {
    import_chipprobe_config $cpcList
    compile_probe
  }

### Editable zone for bitgen ###
  set timing_file [open ${prj_name}_pr.timing r]
  set timing_text [read $timing_file]
  close $timing_file
  foreach field {SWNS STNS HWNS HTNS} {
    set pattern [format {%s: (-?[0-9.]+)ns} $field]
    if {![regexp $pattern $timing_text all slack]} {error "Missing timing result: $field"}
    if {$slack<0} {error "Timing failed: $field=$slack"}
  }
  set area_file [open ${prj_name}_phy.area r]
  set area_text [read $area_file]
  close $area_file
  foreach {kind limit} {lut 19600 reg 19600 bram 64 dsp 29 pll 4} {
    set pattern [format {#%s[[:space:]]+([0-9]+)} $kind]
    if {![regexp $pattern $area_text all count] || $count>$limit} {error "Resource limit exceeded: $kind"}
  }
  drc_check -all -place -route -verbose
  bitgen -bit $prj_name.bit

################################
  upvar chipDebugger chipDebugger
  if { ![info exists chipDebugger] } {
    setup_debugger
  } else { setup_debugger $chipDebugger }
  export_bitgen_param -file .bitgen_param.f 
}
foreach s [lrange $stepList $l $r] {
  step_begin $s
  set ACTIVESTEP $s
  set rc [catch {
    if { [string equal $s $start_step] } { prepare $l }
    ${s}_fun
  } RESULT]
  if { $rc } {
    step_error $s
    return -code error $RESULT
  } else {
    step_end $s
    unset ACTIVESTEP
  }
}
export_flow_status -s $start_step -e $end_step
