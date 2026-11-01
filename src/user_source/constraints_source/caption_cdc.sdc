# Caption held bundles: 12.2ns directed data-path bound.
# Only asynchronous first req/ack stages and same-edge bundle hold are excepted.
# Later synchronizer stages and all business paths remain timed.
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/g_caption$u_caption/request_bundle/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/request_bundle/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {sd_card_bmp_m0/g_caption$u_caption/request_bundle/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/request_bundle/dst_value[*]}]
set_false_path -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/request_bundle/req_sync[0] sd_card_bmp_m0/g_caption$u_caption/request_bundle/ack_sync[0]}]
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/g_caption$u_caption/header_bundle/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/header_bundle/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {sd_card_bmp_m0/g_caption$u_caption/header_bundle/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/header_bundle/dst_value[*]}]
set_false_path -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/header_bundle/req_sync[0] sd_card_bmp_m0/g_caption$u_caption/header_bundle/ack_sync[0]}]
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank0_metadata/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank0_metadata/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank0_metadata/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank0_metadata/dst_value[*]}]
set_false_path -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank0_metadata/req_sync[0] sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank0_metadata/ack_sync[0]}]
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank1_metadata/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank1_metadata/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank1_metadata/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank1_metadata/dst_value[*]}]
set_false_path -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank1_metadata/req_sync[0] sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank1_metadata/ack_sync[0]}]
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank0_release/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank0_release/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank0_release/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank0_release/dst_value[*]}]
set_false_path -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank0_release/req_sync[0] sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank0_release/ack_sync[0]}]
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank1_release/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank1_release/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank1_release/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank1_release/dst_value[*]}]
set_false_path -to [get_regs {sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank1_release/req_sync[0] sd_card_bmp_m0/g_caption$u_caption/u_buffers/bank1_release/ack_sync[0]}]
