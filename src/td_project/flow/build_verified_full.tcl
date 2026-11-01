set project_dir [file normalize [file join [file dirname [info script]] ..]]
set run_dir [file join $project_dir verified_rebuild_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
file mkdir $run_dir
cd $project_dir
import_device eagle_s20.db -package EG4S20BG256
set verified_build_project_file "$project_dir/HDMI1.4b_Transmitter_v1.0.al"
open_project $verified_build_project_file
cd $run_dir
set_param rtl min_control_set 2
set_param rtl min_ripple_len 24
elaborate -top top
export_db formal_elaborate.db
read_adc [file normalize "$project_dir/../user_source/constraints_source/pin.adc"]
read_sdc [file normalize "$project_dir/../user_source/constraints_source/timing.sdc"]
read_sdc [file normalize "$project_dir/../user_source/constraints_source/bundled_data_hold.sdc"]
read_sdc [file normalize "$project_dir/../user_source/constraints_source/sd80_cdc.sdc"]
read_sdc [file normalize "$project_dir/../user_source/constraints_source/caption_cdc.sdc"]
read_sdc -ip rfifo_32_32_512 [file normalize "$project_dir/../user_source/hdl_source/IP/afifo_32_16_256.tcl"]
read_sdc -ip wfifo_32_32_512 [file normalize "$project_dir/../user_source/hdl_source/IP/afifo_16_32_256.tcl"]
read_sdc [file normalize "$project_dir/../user_source/constraints_source/scaler_clock_bridge.sdc"]
optimize_rtl
report_area -file formal_rtl.area
export_db formal_rtl.db
set_param gate pack_effort high
set_param gate pack_seq_in_io off
set_param gate opt_area high
set_param gate map_mode area_prior
set_param gate map_strategy 3
optimize_gate -packarea formal_gate.area
legalize_phy_inst
read_sdc [file normalize "$project_dir/../user_source/constraints_source/scaler_clock_bridge.sdc"]
export_db formal_gate.db
update_timing
report_timing_status -file formal_gate.ts
report_timing_summary -file formal_gate.timing
write_verilog formal_gate.v
report_qor -step gate -file formal_gate.qor
flow_status -file formal_synth_flow.status
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
source [file join $project_dir flow preflight_cluster_soft.tcl]
place
export_db placed.db
set_param route effort routability
set_param route timing normal
set_param route post_route_opt ultra
route
export_db routed_before_hold.db
fix_hold -clock_opt -eco
route -eco
drc_check -all -place -route -verbose
report_area -io_info -file final.area
update_timing -mode final
report_timing_status -file final.ts
report_timing_summary -file final.timing
report_timing -file final_paths.rpt
report_qor -step route -file final.qor
flow_status -file final.status
export_db final.db
write_verilog final.v
set prj_name HDMI1.4b_Transmitter_v1.0
  set timing_file [open final.timing r]
  set timing_text [read $timing_file]
  close $timing_file
  foreach field {SWNS STNS HWNS HTNS} {
    set pattern [format {%s: (-?[0-9.]+)ns} $field]
    if {![regexp $pattern $timing_text all slack]} {error "Missing timing result: $field"}
    if {$slack<0} {error "Timing failed: $field=$slack"}
  }
  set area_file [open final.area r]
  set area_text [read $area_file]
  close $area_file
  foreach {kind limit} {lut 19600 reg 19600 bram 64 dsp 29 pll 4} {
    set pattern [format {#%s[[:space:]]+([0-9]+)} $kind]
    if {![regexp $pattern $area_text all count] || $count>$limit} {error "Resource limit exceeded: $kind"}
  }
  drc_check -all
  bitgen -bit $prj_name.bit
exit
