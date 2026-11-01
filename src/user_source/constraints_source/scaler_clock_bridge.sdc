# Approved true25 bridge only. Original clocks and old121 selectors remain.
# Gray source to first stage bounded20ns; later synchronizer stages stay timed.
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_byte_fifo/wr_gray[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_byte_fifo/wr_sync1[*]}] 20
set_false_path -hold -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_byte_fifo/wr_gray[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_byte_fifo/wr_sync1[*]}]
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_byte_fifo/rd_gray[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_byte_fifo/rd_sync1[*]}] 20
set_false_path -hold -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_byte_fifo/rd_gray[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_byte_fifo/rd_sync1[*]}]
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_rgb_fifo/wr_gray[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_rgb_fifo/wr_sync1[*]}] 20
set_false_path -hold -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_rgb_fifo/wr_gray[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_rgb_fifo/wr_sync1[*]}]
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_rgb_fifo/rd_gray[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_rgb_fifo/rd_sync1[*]}] 20
set_false_path -hold -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_rgb_fifo/rd_gray[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/u_rgb_fifo/rd_sync1[*]}]
set_false_path -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/status_request}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/status_sync[0]}]
# Held error payload, request two-stage synchronization plus a capture cycle.
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/status_error[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/error[*]}] 20
set_false_path -hold -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/status_error[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/error[*]}]
# File size held before START token; capture precedes core_start by one25MHz cycle.
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/file_size[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/file_size_scale[*]}] 20
set_false_path -hold -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/file_size[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/file_size_scale[*]}]
# START asynchronously asserts only the four reset qualifiers; release is synchronous.
set_false_path -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/stream_start}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/reset_source[*] sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/reset_scale[*]}]

# Approved v58: video-reset asynchronous assertion into four source-domain qualifiers only.
set_false_path -from [get_regs {reset_video_sync[2]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/reset_source[*] sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/control_reset_source[*]}]

set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/status_error[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/active}] 20
set_false_path -hold -from [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/status_error[*]}] -to [get_regs {sd_card_bmp_m0/fat32_bmp_reader_m0/g_scaling$u_scaler/active}]
