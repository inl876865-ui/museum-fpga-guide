# Independent SD80 domain: explicit statements for the TD SDC parser.
# This file has no Tcl loops/variables. No blanket clock-domain exceptions.
# Held-until-acknowledged bundle: u_panel_settings
set_max_delay -datapath_only -from [get_regs {u_panel_settings/held_value[*]}] -to [get_regs {u_panel_settings/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {u_panel_settings/held_value[*]}] -to [get_regs {u_panel_settings/dst_value[*]}]
set_false_path -to [get_regs {u_panel_settings/req_sync[0] u_panel_settings/ack_sync[0]}]
# Held-until-acknowledged bundle: u_panel_period
set_max_delay -datapath_only -from [get_regs {u_panel_period/held_value[*]}] -to [get_regs {u_panel_period/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {u_panel_period/held_value[*]}] -to [get_regs {u_panel_period/dst_value[*]}]
set_false_path -to [get_regs {u_panel_period/req_sync[0] u_panel_period/ack_sync[0]}]
# Held-until-acknowledged bundle: u_audio_settings
set_max_delay -datapath_only -from [get_regs {u_audio_settings/held_value[*]}] -to [get_regs {u_audio_settings/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {u_audio_settings/held_value[*]}] -to [get_regs {u_audio_settings/dst_value[*]}]
set_false_path -to [get_regs {u_audio_settings/req_sync[0] u_audio_settings/ack_sync[0]}]
# Held-until-acknowledged bundle: u_audio_source_settings
set_max_delay -datapath_only -from [get_regs {u_audio_source_settings/held_value[*]}] -to [get_regs {u_audio_source_settings/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {u_audio_source_settings/held_value[*]}] -to [get_regs {u_audio_source_settings/dst_value[*]}]
set_false_path -to [get_regs {u_audio_source_settings/req_sync[0] u_audio_source_settings/ack_sync[0]}]
# Held-until-acknowledged bundle: u_playback_options_settings
set_max_delay -datapath_only -from [get_regs {u_playback_options_settings/held_value[*]}] -to [get_regs {u_playback_options_settings/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {u_playback_options_settings/held_value[*]}] -to [get_regs {u_playback_options_settings/dst_value[*]}]
set_false_path -to [get_regs {u_playback_options_settings/req_sync[0] u_playback_options_settings/ack_sync[0]}]
# Held-until-acknowledged bundle: u_thumbnail_ready_settings
set_max_delay -datapath_only -from [get_regs {u_thumbnail_ready_settings/held_value[*]}] -to [get_regs {u_thumbnail_ready_settings/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {u_thumbnail_ready_settings/held_value[*]}] -to [get_regs {u_thumbnail_ready_settings/dst_value[*]}]
set_false_path -to [get_regs {u_thumbnail_ready_settings/req_sync[0] u_thumbnail_ready_settings/ack_sync[0]}]
# Held-until-acknowledged bundle: u_thumbnail_view_settings
set_max_delay -datapath_only -from [get_regs {u_thumbnail_view_settings/held_value[*]}] -to [get_regs {u_thumbnail_view_settings/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {u_thumbnail_view_settings/held_value[*]}] -to [get_regs {u_thumbnail_view_settings/dst_value[*]}]
set_false_path -to [get_regs {u_thumbnail_view_settings/req_sync[0] u_thumbnail_view_settings/ack_sync[0]}]
# Held-until-acknowledged bundle: u_screen_menu_settings
set_max_delay -datapath_only -from [get_regs {u_screen_menu_settings/held_value[*]}] -to [get_regs {u_screen_menu_settings/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {u_screen_menu_settings/held_value[*]}] -to [get_regs {u_screen_menu_settings/dst_value[*]}]
set_false_path -to [get_regs {u_screen_menu_settings/req_sync[0] u_screen_menu_settings/ack_sync[0]}]
# Held-until-acknowledged bundle: u_fade_settings
set_max_delay -datapath_only -from [get_regs {u_fade_settings/held_value[*]}] -to [get_regs {u_fade_settings/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {u_fade_settings/held_value[*]}] -to [get_regs {u_fade_settings/dst_value[*]}]
set_false_path -to [get_regs {u_fade_settings/req_sync[0] u_fade_settings/ack_sync[0]}]
# Held-until-acknowledged bundle: sd_card_bmp_m0/g_audio_image_bind$binding_control/file_metadata
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/g_audio_image_bind$binding_control/file_metadata/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_audio_image_bind$binding_control/file_metadata/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {sd_card_bmp_m0/g_audio_image_bind$binding_control/file_metadata/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_audio_image_bind$binding_control/file_metadata/dst_value[*]}]
set_false_path -to [get_regs {sd_card_bmp_m0/g_audio_image_bind$binding_control/file_metadata/req_sync[0] sd_card_bmp_m0/g_audio_image_bind$binding_control/file_metadata/ack_sync[0]}]
# Held-until-acknowledged bundle: sd_card_bmp_m0/g_audio_image_bind$binding_control/started_metadata
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/g_audio_image_bind$binding_control/started_metadata/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_audio_image_bind$binding_control/started_metadata/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {sd_card_bmp_m0/g_audio_image_bind$binding_control/started_metadata/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_audio_image_bind$binding_control/started_metadata/dst_value[*]}]
set_false_path -to [get_regs {sd_card_bmp_m0/g_audio_image_bind$binding_control/started_metadata/req_sync[0] sd_card_bmp_m0/g_audio_image_bind$binding_control/started_metadata/ack_sync[0]}]
# Held-until-acknowledged bundle: sd_card_bmp_m0/g_audio_auto$g_progress_metadata$file_metadata
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/g_audio_auto$g_progress_metadata$file_metadata/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_audio_auto$g_progress_metadata$file_metadata/dst_value[*]}] 12.2
set_false_path -hold -from [get_regs {sd_card_bmp_m0/g_audio_auto$g_progress_metadata$file_metadata/held_value[*]}] -to [get_regs {sd_card_bmp_m0/g_audio_auto$g_progress_metadata$file_metadata/dst_value[*]}]
set_false_path -to [get_regs {sd_card_bmp_m0/g_audio_auto$g_progress_metadata$file_metadata/req_sync[0] sd_card_bmp_m0/g_audio_auto$g_progress_metadata$file_metadata/ack_sync[0]}]
# Single-bit level/toggle asynchronous input to FIRST stage only.
set_false_path -to [get_regs {sd_card_bmp_m0/g_audio_image_bind$binding_control/allow_sync[0]}]
set_false_path -to [get_regs {sd_card_bmp_m0/playback_end_sync[0]}]
set_false_path -to [get_regs {sd_card_bmp_m0/g_audio_auto$switch_ready_sync[0]}]
set_false_path -to [get_regs {sd_card_bmp_m0/g_audio_auto$stream_reset_pixel[0]}]
set_false_path -to [get_regs {u_media_frame_reader/g_diagonal_reader$u_read_engine/req_sync[0]}]
set_false_path -to [get_regs {u_media_frame_reader/g_diagonal_reader$u_read_engine/ack_pipe[0]}]
set_false_path -to [get_regs {u_thumbnail_capture/needed_sync[0]}]
# Gray pointer first-stage data bound; subsequent stages stay timed.
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/g_audio_auto$u_audio_file_fifo/wr_gray[*]}] -to [get_regs {sd_card_bmp_m0/g_audio_auto$u_audio_file_fifo/wr_sync1[*]}] 12.2
set_false_path -hold -from [get_regs {sd_card_bmp_m0/g_audio_auto$u_audio_file_fifo/wr_gray[*]}] -to [get_regs {sd_card_bmp_m0/g_audio_auto$u_audio_file_fifo/wr_sync1[*]}]
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/g_audio_auto$u_audio_file_fifo/rd_gray[*]}] -to [get_regs {sd_card_bmp_m0/g_audio_auto$u_audio_file_fifo/rd_sync1[*]}] 12.2
set_false_path -hold -from [get_regs {sd_card_bmp_m0/g_audio_auto$u_audio_file_fifo/rd_gray[*]}] -to [get_regs {sd_card_bmp_m0/g_audio_auto$u_audio_file_fifo/rd_sync1[*]}]
set_false_path -to [get_regs {sd_card_bmp_m0/g_audio_auto$u_audio_file_fifo/finished_sync[0]}]
# Gray pointer first-stage data bound; subsequent stages stay timed.
# Shipped FIFO asynchronous reset input; release to payload stays timed.
set_false_path -from [get_regs {u_thumbnail_capture/u_writer/fifo_aclr}] -to [get_regs {u_thumbnail_capture/u_fifo/asy_w_rst0 u_thumbnail_capture/u_fifo/asy_w_rst1 u_thumbnail_capture/u_fifo/asy_r_rst0 u_thumbnail_capture/u_fifo/asy_r_rst1}]
# Shipped FIFO asynchronous reset input; release to payload stays timed.
set_false_path -from [get_regs {u_media_frame_loader/u_write_engine/fifo_aclr}] -to [get_regs {u_media_frame_loader/u_write_fifo/asy_w_rst0 u_media_frame_loader/u_write_fifo/asy_w_rst1 u_media_frame_loader/u_write_fifo/asy_r_rst0 u_media_frame_loader/u_write_fifo/asy_r_rst1}]
# Shipped FIFO asynchronous reset input; release to payload stays timed.
set_false_path -from [get_regs {u_media_frame_reader/g_diagonal_reader$u_read_engine/fifo_clear}] -to [get_regs {u_media_frame_reader/u_read_fifo/asy_w_rst0 u_media_frame_reader/u_read_fifo/asy_w_rst1 u_media_frame_reader/u_read_fifo/asy_r_rst0 u_media_frame_reader/u_read_fifo/asy_r_rst1}]

# Remaining held frame descriptor and first-stage status boundaries.
# Frame index/track are held until the synchronized frame acknowledgement.
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/u_media_player_control/frame_commit_request_index[*]}] -to [get_regs {sd_card_bmp_m0/u_media_player_control/u_media_frame_commit/index_sync0[*]}] 12.2
set_false_path -hold -from [get_regs {sd_card_bmp_m0/u_media_player_control/frame_commit_request_index[*]}] -to [get_regs {sd_card_bmp_m0/u_media_player_control/u_media_frame_commit/index_sync0[*]}]
set_max_delay -datapath_only -from [get_regs {sd_card_bmp_m0/u_media_player_control/request_track[*]}] -to [get_regs {sd_card_bmp_m0/u_media_player_control/u_media_frame_commit/track_sync0[*]}] 12.2
set_false_path -hold -from [get_regs {sd_card_bmp_m0/u_media_player_control/request_track[*]}] -to [get_regs {sd_card_bmp_m0/u_media_player_control/u_media_frame_commit/track_sync0[*]}]
set_false_path -to [get_regs {sd_card_bmp_m0/u_media_player_control/u_media_frame_commit/request_sync[0]}]
set_false_path -to [get_regs {sd_card_bmp_m0/u_media_player_control/u_media_frame_commit/acknowledge_sync[0]}]
set_false_path -to [get_regs {sd_card_bmp_m0/u_media_player_control/u_media_frame_commit/bound_sync[0]}]
set_false_path -to [get_regs {sd_card_bmp_m0/u_media_player_control/u_media_frame_commit/applied_sync[0]}]
set_false_path -to [get_regs {u_diagonal_control/auto_sync[0]}]
set_false_path -to [get_regs {u_auto_fade/auto_sync[0]}]
set_false_path -to [get_regs {u_media_audio_video_control/state_sync0[*]}]
set_false_path -to [get_regs {u_media_audio_video_control/valid_sync[0]}]
set_false_path -to [get_regs {audio_switch_sync[0]}]
set_false_path -to [get_regs {sd_card_bmp_m0/write_ack_sync[0]}]
set_false_path -to [get_regs {sd_card_bmp_m0/wrfin_tgl_sync[0]}]
# Memory reset async assertion into write-clock reset qualifier only.
# Qualifier D paths and release to fifo_overflow remain timed.
set_false_path -from [get_regs {reset_mem_sync[2]}] -to [get_regs {u_media_frame_loader/write_reset_sync[*]}]

# Manual cue held-toggle input: only source-to-first-stage capture.
set_false_path -from [get_regs {sd_card_bmp_m0/manual_cue_toggle}] -to [get_regs {sd_card_bmp_m0/g_transition_cue$manual_sync[0]}]

# Approved v55: asynchronous assertion only into two reset qualifiers; ordinary50MHz logic remains timed.
set_false_path -from [get_regs {u_media_frame_loader/u_write_engine/fifo_aclr}] -to [get_regs {u_media_frame_loader/write_reset_sync[*]}]
