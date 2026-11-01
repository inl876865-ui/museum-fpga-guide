# The source holds each panel value until its request crosses two destination
# synchronizers, a further capture cycle passes, and acknowledgement returns.
# Preserve setup timing; only same-edge hold checks on these data bundles differ
# from the implemented handshake sampling cycle.
set_false_path -hold -from [get_regs {u_panel_settings/held_value[*]}] -to [get_regs {u_panel_settings/dst_value[*]}]
set_false_path -hold -from [get_regs {u_panel_period/held_value[*]}] -to [get_regs {u_panel_period/dst_value[*]}]

# Asynchronous inputs terminate at the first synchronizer stage only.
set_false_path -to [get_regs {u_panel_settings/req_sync[0] u_panel_period/req_sync[0]}]
set_false_path -to [get_regs {u_panel_settings/ack_sync[0] u_panel_period/ack_sync[0]}]
set_false_path -to [get_regs {panel_state_sync0[*] panel_error_sync0[*] panel_valid_sync[0]}]
