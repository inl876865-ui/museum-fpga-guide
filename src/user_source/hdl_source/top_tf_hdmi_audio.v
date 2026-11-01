
module top(
    input                       clk,
    input                       rst_n,          // SW1/C8: up runs, down holds reset
    input                       key_confirm_n,  // KEY1/A2: confirm
    input [1:0]                 main_keys_sw,   // {SW2/C7, SW3/C6}
    input                       key1,           // 实体 KEY2/B2：加、下一张、自动页开启轮播
    input                       key2,           // 实体 KEY4/C1：自动/音量/周期/保存/正常页面
    input                       key3,           // 实体 KEY3/B1：减、上一张

    output [7:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso,
    // Independent user W25Q64; not the FPGA boot Flash.
    input                       flash_miso,
    output                      flash_cs_n, flash_sclk, flash_mosi, flash_wp_n, flash_hold_n,
    input                       thumbnail_switch // SW4/C5: up shows thumbnails
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire sys_feedback_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data_transition;
wire [23:0] vout_data;
wire        display_valid;

wire [5:0]  state_code;
wire [2:0] storage_error;
reg [2:0] panel_error_sync0, panel_error_sync1, panel_error_sync2;
reg [2:0] panel_error;
wire [7:0] panel_dig_n;
reg [5:0] panel_state_sync0, panel_state_sync1, panel_state_sync2;
reg [1:0] panel_valid_sync;
reg [4:0] panel_media_id;
wire [4:0] pixel_image_index;
reg panel_picture_valid;
reg panel_pic_event;

reg         video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;
wire        video_frame_start;
wire [11:0] video_timing_x, video_timing_y;
wire [1:0]  pixel_active_index;
wire        pixel_active_valid;
wire        auto_frame_commit;
wire [1:0]  auto_fade_read_index;
wire [7:0]  auto_fade_alpha;
wire [7:0]  transition_alpha;
wire        transition_wipe_active;
wire [4:0]  transition_ramp;

wire        sd_card_write_en;
wire full_writer_ready,thumbnail_pixel_ready;
wire sd_card_write_ready=full_writer_ready && thumbnail_pixel_ready;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;
wire [31:0] image_complete;
wire        frame_commit_request_toggle;
wire [1:0]  frame_commit_request_index;
wire        frame_commit_acknowledge_toggle;
wire        writer_fifo_overflow;
wire        reader_underflow;
wire        reader_fifo_overflow;
wire        App_wr_busy;
wire        App_rd_busy;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// 第四讲：像素时钟域 PCM 音频与 HDMI 符号
localparam integer AUTO_PLAY_MS = 3000;  // 与 PRD 页共用的实际轮播等待参数
localparam [5:0] AUTO_PLAY_SECONDS = AUTO_PLAY_MS / 1000;
localparam [7:0] AUDIO_VOLUME = 8'd128;  // 复位默认值
wire [7:0] player_volume;
wire player_volume_mode;
wire player_fade_mode;
wire [1:0] player_fade_level;
wire player_period_mode;
wire [5:0] player_period_seconds;
wire [16:0] panel_settings;
wire [1:0] pixel_fade_level;
wire [6:0] panel_period;
wire player_save_mode;
wire player_auto_mode;
wire player_auto_enabled;
wire player_source_mode,player_track_mode,player_source_wav,player_audio_paused;
wire player_menu_open,player_menu_level,player_main_keys_music,player_main_keys_thumbnail;
wire [1:0] player_playback_mode;
wire [3:0] pixel_playback_options;
wire [1:0] player_menu_group;
wire [2:0] player_menu_item;
wire player_audio_image_bind,player_progress_visible;
wire player_diagonal_selected,diagonal_active;
wire signed [15:0] cue_sample;
wire cue_valid,cue_ready,cue_trigger;
wire [1:0] diagonal_old_index;
wire [6:0] diagonal_shift;
wire [23:0] vout_data_glow;
wire [3:0] progress_file_tag;
wire [31:0] progress_file_size,progress_played_samples;
wire progress_available,progress_valid,progress_long_time;
wire [23:0] progress_elapsed_bcd,progress_total_bcd;
wire [4:0] progress_fill_pixels;
wire [3:0] player_track_number,player_track_count;
wire [63:0] pixel_menu_snapshot;
reg [60:0] frame_menu_snapshot;
wire [1:0] player_menu_transparency,player_thumbnail_transparency;
wire player_visual_enabled,player_image_page;
wire [7:0] player_brightness,player_contrast;
wire [16:0] pixel_picture_settings;
assign pixel_picture_settings=frame_menu_snapshot[51:35];
wire [23:0] vout_data_picture;
wire picture_hs,picture_vs,picture_de;
wire [9:0] picture_x;
wire player_thumbnail_view,player_thumbnail_waiting,thumbnail_load_active;
wire [4:0] player_thumbnail_focus,thumbnail_load_index,thumbnail_publish_index;
wire [5:0] thumbnail_count;
wire [31:0] thumbnail_ready_mem,thumbnail_ready_sd,thumbnail_failed;
wire [3:0] thumbnail_ready_page_sd=thumbnail_ready_sd >> {player_thumbnail_focus[4:2],2'b00};
wire [3:0] thumbnail_failed_page_sd=thumbnail_failed >> {player_thumbnail_focus[4:2],2'b00};
wire thumbnail_publish_toggle,thumbnail_invalidate_toggle;
wire [20:0] pixel_thumbnail_settings;
reg [20:0] frame_thumbnail_settings;
reg [1:0] thumbnail_mode_mem;
wire thumb_hs,thumb_vs,thumb_de,thumb_frame_start,thumb_consume_row;
wire [9:0] thumb_x,thumb_pixel_address;
wire [8:0] thumb_display_row,thumb_consumed_row;
wire [23:0] vout_data_thumbnail;
wire [31:0] thumb_pixel_data;
wire [1:0] thumb_display_mask;
wire [3:0] memory_grant;
wire full_read_pending,full_write_pending,small_read_pending,small_write_pending;
wire full_read_busy,full_write_busy,small_read_busy,small_write_busy;
wire full_read_en,full_write_en,small_read_en,small_write_en;
wire [20:0] full_read_address,full_write_address,small_read_address,small_write_address;
wire [31:0] full_write_data,small_write_data;
wire [3:0] full_write_mask;
wire full_write_ack,full_write_finish,full_writer_overflow,small_writer_overflow;
wire [23:0] vout_data_waveform;
wire player_caption_enabled;
wire caption_hs,caption_vs,caption_de;
wire [9:0] caption_x;
wire [23:0] vout_data_caption;
wire [11:0] caption_bitmap_address;
wire caption_bitmap_bank;
wire [7:0] caption_bitmap_byte;
wire caption_frame_visible,caption_frame_bank;
wire [9:0] caption_frame_width;
wire [2:0] caption_frame_color_id;
wire signed [11:0] caption_frame_text_x;
reg [1:0] caption_content_valid;
wire pixel_menu_visible;
reg menu_video_hsync,menu_video_vsync,menu_video_de,menu_active_valid;
reg [9:0] menu_video_x;
wire pixel_source_wav;
wire [1:0] pixel_audio_control;
wire pixel_pause_requested,audio_pause_ack;
assign pixel_source_wav=pixel_audio_control[0];
assign pixel_pause_requested=pixel_audio_control[1];
wire [1:0] audio_status;
wire wav_audio_switching,audio_switch_ready;
reg [1:0] audio_switch_sync;
wire [1:0] player_save_status;
wire [7:0] pixel_volume;
wire [3:0] video_osd_settings;
wire [23:0] vout_data_osd;
wire [23:0] vout_data_status;
reg panel_volume_mode_q;
wire panel_mode_exit = panel_volume_mode_q &&
                       !(panel_settings[8] || panel_settings[9] ||
                         panel_settings[10] || panel_settings[16] || panel_period[6]);
wire [9:0] video_x;
wire [1:0] media_id;
wire [7:0] audio_volume;
wire video_timing_locked;
wire sequence_error;
wire tone_overflow;
wire pcm_contract_error;
wire blip_active;
wire pcm_tap_valid;
wire signed [15:0] pcm_tap_left;
wire wav_sample_valid, wav_sample_ready, wav_audio_active, wav_audio_end;
wire signed [15:0] wav_sample_left, wav_sample_right;
always @(posedge video_clk or posedge rst_video) begin
    if(rst_video) audio_switch_sync<=0;
    else audio_switch_sync<={audio_switch_sync[0],wav_audio_switching};
end

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 音频链路
wire rst_all;
wire sys_pll_lock, video_pll_lock, sd_pll_lock;
wire pll_reset;
// 上电先保持 PLL 复位约 1.31 ms，再等待三个 PLL 稳定锁定。
// power_on_done 不依赖 PLL 锁定，避免“复位导致无法锁定”的环路。
reg [15:0] power_on_count = 16'd0;
reg power_on_done = 1'b0;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        power_on_count <= 16'd0;
        power_on_done <= 1'b0;
    end else if (!power_on_done) begin
        if (&power_on_count)
            power_on_done <= 1'b1;
        else
            power_on_count <= power_on_count + 16'd1;
    end
end
assign pll_reset = ~rst_n | ~power_on_done;
pll_startup_guard u_pll_startup_guard (
    .clk(clk), .rst_n(rst_n), .power_on_done(power_on_done),
    .sys_pll_lock(sys_pll_lock && sd_pll_lock), .video_pll_lock(video_pll_lock),
    .rst_all(rst_all)
);

// 上电复位异步置位，各时钟域延迟三拍同步释放。
(* async_reg = "true" *) reg [2:0] reset_sd_sync = 3'b111;
(* async_reg = "true" *) reg [2:0] reset_mem_sync = 3'b111;
(* async_reg = "true" *) reg [2:0] reset_video_sync = 3'b111;
(* async_reg = "true" *) reg [2:0] reset_serial_sync = 3'b111;
(* async_reg = "true" *) reg [2:0] reset_ui_sync = 3'b111;
(* async_reg = "true" *) reg [2:0] sdram_init_sync = 3'b000;
wire rst_ui = reset_ui_sync[2];
wire rst_sd = reset_sd_sync[2];
wire rst_mem = reset_mem_sync[2];
wire rst_video = reset_video_sync[2];
wire rst_serial = reset_serial_sync[2];
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) reset_sd_sync <= 3'b111;
    else reset_sd_sync <= {reset_sd_sync[1:0], 1'b0};
end
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all) reset_mem_sync <= 3'b111;
    else reset_mem_sync <= {reset_mem_sync[1:0], 1'b0};
end
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) reset_video_sync <= 3'b111;
    else reset_video_sync <= {reset_video_sync[1:0], 1'b0};
end
always @(posedge hdmi_5x_clk or posedge rst_all) begin
    if (rst_all) reset_serial_sync <= 3'b111;
    else reset_serial_sync <= {reset_serial_sync[1:0], 1'b0};
end

// 50 MHz 面板也在本域同步释放，避免 PLL 锁定信号直接释放业务复位。
always @(posedge clk or posedge rst_all) begin
    if (rst_all) reset_ui_sync <= 3'b111;
    else reset_ui_sync <= {reset_ui_sync[1:0], 1'b0};
end
// SDRAM 初始化标志从 40 MHz 同步到 50 MHz 存储业务域。
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) sdram_init_sync <= 3'b000;
    else sdram_init_sync <= {sdram_init_sync[1:0], Sdr_init_done};
end

// 原 sys_pll 保留自身100 MHz反馈和SDRAM40 MHz/采样相位；SD独立50 MHz。
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sys_feedback_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .extlock    (sys_pll_lock),
    .reset      (pll_reset)
);

sd_pll sd_pll_m0(
    .refclk(clk), .reset(pll_reset),
    .clk0_out(sd_card_clk), .extlock(sd_pll_lock)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .extlock    (video_pll_lock),
    .reset      (pll_reset)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

wire clock_time_stable;
wire [1:0] clock_edit_owner;
wire [2:0] clock_command;
wire [23:0] clock_time;
wire [15:0] clock_timer,clock_edit;
wire clock_valid,clock_timer_enabled,clock_edit_minutes,clock_sleep;
wire clock_display_enabled;
(* async_reg="true" *) reg [1:0] clock_sleep_sd_sync;
reg clock_sleep_frame;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if(rst_sd) clock_sleep_sd_sync<=0;
    else clock_sleep_sd_sync<={clock_sleep_sd_sync[0],clock_sleep};
end
always @(posedge video_clk or posedge rst_video) begin
    if(rst_video) clock_sleep_frame<=0;
    else if(video_frame_start) clock_sleep_frame<=clock_sleep;
end
wire [1:0] clock_selection=pixel_menu_snapshot[33] && pixel_menu_snapshot[32] &&
    {pixel_menu_snapshot[51],pixel_menu_snapshot[31:30]}==7 ?
    ({pixel_menu_snapshot[56],pixel_menu_snapshot[29:28]}==0 ? 2'd1 :
     {pixel_menu_snapshot[56],pixel_menu_snapshot[29:28]}==1 ? 2'd2 :
     ({pixel_menu_snapshot[56],pixel_menu_snapshot[29:28]}==2 ||
      {pixel_menu_snapshot[56],pixel_menu_snapshot[29:28]}==3) ? 2'd3 : 2'd0) : 2'd0;
wire menu_label_request,menu_label_grant,menu_label_response_valid;
wire [8:0] menu_label_address;
wire [6:0] menu_label_glyph;
clock_timer_control #(.ENABLE_SHARED_LABEL_ROM(1),.ENABLE_LOW_POWER_MENU(1)) u_clock_timer (
    .label_request(menu_label_request),.label_address(menu_label_address),.label_grant(menu_label_grant),
    .label_response_valid(menu_label_response_valid),.label_glyph(menu_label_glyph),
    .clk(video_clk),.rst(rst_video),.command(pixel_menu_snapshot[63:61]),.selection(clock_selection),
    .time_bcd(clock_time),.time_valid(clock_valid),.timer_enabled(clock_timer_enabled),
    .clock_display_enabled(clock_display_enabled),
    .sleeping(clock_sleep),.timer_bcd(clock_timer),.edit_bcd(clock_edit),.edit_minutes(clock_edit_minutes),.time_stable(clock_time_stable),.edit_owner(clock_edit_owner));

// ===================== TF 多图扫描与四图缓存 =====================
wire [8:0] bmp_buffer_address;
wire bmp_buffer_write;
wire [7:0] bmp_buffer_write_data,bmp_buffer_read_data,caption_font_byte;
wire [6:0] caption_font_address;
scaling_sector_font_ram u_scaling_sector_font_ram (
    .pixel_clk(video_clk),.sd_clk(sd_card_clk),
    .font_address(caption_font_address),.font_byte(caption_font_byte),
    .sector_address(bmp_buffer_address),.sector_write(bmp_buffer_write),
    .sector_write_data(bmp_buffer_write_data),.sector_read_data(bmp_buffer_read_data));
sd_card_bmp #(
    .CLK_FREQ_HZ       (50_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (3'd4),
    .AUTO_PLAY_MS      (AUTO_PLAY_MS),
    .TRANSITION_FRAMES (0),
    .AUDIO_AUTO_FILES (1),
    .USE_SCREEN_MENU (1),
    .ENABLE_AUDIO_CONTROL (1),.ENABLE_PLAY_OPTIONS(1),.MAX_IMAGES(32),.ENABLE_AUDIO_VISUAL(1),.ENABLE_PICTURE_ADJUST(1),.ENABLE_THUMBNAILS(1),.RESIDENT_THUMBNAILS(1),.FULLSCREEN_THUMBNAILS(1),.ENABLE_MENU_TRANSPARENCY(1),.ENABLE_CONFIRM_KEY(1),.ENABLE_SWITCH_MODE(1),.DEMO_MENU(2),.ENABLE_THUMB_TRANSPARENCY(1),.ENABLE_AUDIO_IMAGE_BIND(1),.ENABLE_TRANSITION_CUE(1),.ENABLE_DIAGONAL_TRANSITION(1),.ENABLE_AUDIO_PROGRESS(1),.ENABLE_CAPTION(1),.FIXED_OPAQUE_THUMBNAILS(1),.ENABLE_ADAPTIVE_SCALING(1),.ENABLE_SHARED_SCALING_RAM(1),.ENABLE_SW4_THUMBNAILS(1),.ENABLE_FULL_CONFIG_SAVE(1),.ENABLE_CLOCK_TIMER(1),.ENABLE_LOW_POWER_MENU(1)
) sd_card_bmp_m0(
    .display_sleep(clock_sleep_sd_sync[1]),.clock_command(clock_command),
    .bmp_buffer_address(bmp_buffer_address),.bmp_buffer_write(bmp_buffer_write),
    .bmp_buffer_write_data(bmp_buffer_write_data),.bmp_buffer_read_data(bmp_buffer_read_data),
    .clk               (sd_card_clk),
    .rst               (rst_sd),
    .startup_ready     (sdram_init_sync[2]),
    .key_next          (key1),
    .key_auto          (key2),
    .key_prev          (key3),
    .key_confirm       (key_confirm_n),
    .main_keys_sw      (main_keys_sw),
    .thumbnail_switch(thumbnail_switch),
    .period_cfg_valid  (1'b0),
    .period_cfg_cycles (32'd0),
    .volume            (player_volume),
    .volume_mode       (player_volume_mode),
    .fade_mode(player_fade_mode), .fade_level(player_fade_level),
    .period_mode(player_period_mode), .period_seconds(player_period_seconds),
    .save_mode(player_save_mode), .save_status(player_save_status),
    .auto_mode(player_auto_mode), .auto_enabled(player_auto_enabled),
    .source_mode(player_source_mode),.track_mode(player_track_mode),
    .source_wav(player_source_wav),.audio_paused(player_audio_paused),.track_number(player_track_number),
    .playback_mode(player_playback_mode),.main_keys_music(player_main_keys_music),.main_keys_thumbnail(player_main_keys_thumbnail),
    .track_count(player_track_count),
    .menu_open(player_menu_open),.menu_level(player_menu_level),
    .menu_group(player_menu_group),.menu_item(player_menu_item),.cue_trigger(cue_trigger),.cue_sample_ready(cue_ready),.cue_sample(cue_sample),.cue_sample_valid(cue_valid),
    .diagonal_selected(player_diagonal_selected),.audio_image_bind(player_audio_image_bind),.progress_visible(player_progress_visible),
    .caption_enabled(player_caption_enabled),
    .caption_pixel_enabled(frame_menu_snapshot[60]),.caption_pixel_menu_open(frame_menu_snapshot[33]),
    .caption_pixel_source_wav(pixel_source_wav),
    .caption_bitmap_address(caption_bitmap_address),.caption_bitmap_bank(caption_bitmap_bank),
    .caption_bitmap_byte(caption_bitmap_byte),.caption_frame_visible(caption_frame_visible),
    .caption_frame_bank(caption_frame_bank),.caption_frame_width(caption_frame_width),.caption_frame_text_x(caption_frame_text_x),.caption_frame_color_id(caption_frame_color_id),
    .progress_file_tag(progress_file_tag),.progress_file_size(progress_file_size),
    .progress_played_samples(progress_played_samples),.progress_available(progress_available),.menu_transparency(player_menu_transparency),.thumbnail_transparency(player_thumbnail_transparency),.visual_enabled(player_visual_enabled),
    .image_page(player_image_page),.brightness(player_brightness),.contrast(player_contrast),
    .thumbnail_ready(thumbnail_ready_sd),.thumbnail_view(player_thumbnail_view),
    .thumbnail_waiting(player_thumbnail_waiting),.thumbnail_focus(player_thumbnail_focus),
    .thumbnail_load_index(thumbnail_load_index),.thumbnail_load_active(thumbnail_load_active),
    .thumbnail_image_count(thumbnail_count),.thumbnail_failed(thumbnail_failed),
    .thumbnail_publish_toggle(thumbnail_publish_toggle),.thumbnail_publish_index(thumbnail_publish_index),
    .thumbnail_invalidate_toggle(thumbnail_invalidate_toggle),
    .flash_miso(flash_miso), .flash_cs_n(flash_cs_n), .flash_sclk(flash_sclk),
    .flash_mosi(flash_mosi), .flash_wp_n(flash_wp_n), .flash_hold_n(flash_hold_n),
    .state_code        (state_code),
    .error_code        (storage_error),
    .write_ready       (sd_card_write_ready),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),
    .image_complete    (image_complete),
    .frame_commit_request_toggle(frame_commit_request_toggle),
    .frame_commit_request_index(frame_commit_request_index),
    .frame_commit_acknowledge_toggle(frame_commit_acknowledge_toggle),
    .auto_frame_commit(auto_frame_commit),
    .pixel_clk(video_clk), .pixel_rst(rst_video),
    .frame_start(video_frame_start),
    .active_index(pixel_active_index), .active_valid(pixel_active_valid),
    .transition_alpha(transition_alpha),
    .transition_wipe_active(transition_wipe_active),
    .transition_ramp(transition_ramp),
    .write_fifo_overflow(writer_fifo_overflow),
    .audio_sample_valid(wav_sample_valid),
    .audio_sample_ready(wav_sample_ready),
    .audio_sample_left(wav_sample_left),
    .audio_sample_right(wav_sample_right),
    .audio_active(wav_audio_active),
    .audio_end(wav_audio_end),
    .audio_switching(wav_audio_switching),
    .audio_switch_ready(audio_switch_ready),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

// 握手期间源数据保持不变；目的域等待请求同步后整体接收。
player_settings_cdc #(.WIDTH(17),
    .RESET_VALUE({9'b0,AUDIO_VOLUME})) u_panel_settings (
    .src_clk(sd_card_clk), .src_rst(rst_sd),
    .src_value({player_fade_mode,player_fade_level,
                player_save_status,player_auto_enabled,player_auto_mode,
                player_save_mode,player_volume_mode,player_volume}),
    .dst_clk(clk), .dst_rst(rst_ui), .dst_value(panel_settings)
);
player_settings_cdc #(.WIDTH(7),
    .RESET_VALUE({1'b0,AUTO_PLAY_SECONDS})) u_panel_period (
    .src_clk(sd_card_clk), .src_rst(rst_sd),
    .src_value({player_period_mode,player_period_seconds}),
    .dst_clk(clk), .dst_rst(rst_ui), .dst_value(panel_period)
);
player_settings_cdc #(.WIDTH(8), .RESET_VALUE(AUDIO_VOLUME)) u_audio_settings (
    .src_clk(sd_card_clk), .src_rst(rst_sd), .src_value(player_volume),
    .dst_clk(video_clk), .dst_rst(rst_video), .dst_value(pixel_volume)
);
player_settings_cdc #(.WIDTH(2), .RESET_VALUE(2'b01)) u_audio_source_settings (
    .src_clk(sd_card_clk),.src_rst(rst_sd),.src_value({player_audio_paused,player_source_wav}),
    .dst_clk(video_clk),.dst_rst(rst_video),.dst_value(pixel_audio_control)
);
player_settings_cdc #(.WIDTH(4),.RESET_VALUE(4'd0)) u_playback_options_settings (
    .src_clk(sd_card_clk),.src_rst(rst_sd),
    .src_value({player_main_keys_thumbnail,player_main_keys_music,player_playback_mode}),
    .dst_clk(video_clk),.dst_rst(rst_video),.dst_value(pixel_playback_options)
);
player_settings_cdc #(.WIDTH(32),.RESET_VALUE(32'd0)) u_thumbnail_ready_settings (
    .src_clk(ext_mem_clk),.src_rst(rst_mem),.src_value(thumbnail_ready_mem),
    .dst_clk(sd_card_clk),.dst_rst(rst_sd),.dst_value(thumbnail_ready_sd)
);
player_settings_cdc #(.WIDTH(21),.RESET_VALUE(21'd0)) u_thumbnail_view_settings (
    .src_clk(sd_card_clk),.src_rst(rst_sd),
    .src_value({player_thumbnail_waiting,player_thumbnail_view,player_thumbnail_focus,
                thumbnail_count,thumbnail_failed_page_sd,thumbnail_ready_page_sd}),
    .dst_clk(video_clk),.dst_rst(rst_video),.dst_value(pixel_thumbnail_settings)
);
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if(rst_mem) thumbnail_mode_mem<=0;
    else thumbnail_mode_mem<={thumbnail_mode_mem[0],frame_thumbnail_settings[19]};
end
player_settings_cdc #(.WIDTH(64),.RESET_VALUE({1'b1,1'b0,1'b1,2'd0,2'd2,2'd2,52'h7fc0400000000})) u_screen_menu_settings (
    .src_clk(sd_card_clk),.src_rst(rst_sd),
    .src_value({clock_command,player_caption_enabled,player_diagonal_selected,player_progress_visible,player_audio_image_bind,player_menu_item[2],player_thumbnail_transparency,player_menu_transparency,player_image_page,player_brightness,player_contrast,
                player_visual_enabled,player_menu_open,player_menu_level,
                player_menu_group,player_menu_item[1:0],
                player_auto_enabled,player_source_wav,
                player_period_seconds,player_fade_level,player_volume,
                player_track_number,player_track_count,player_save_status}),
    .dst_clk(video_clk),.dst_rst(rst_video),
    .dst_value(pixel_menu_snapshot)
);
player_settings_cdc #(.WIDTH(2), .RESET_VALUE(2'd1)) u_fade_settings (
    .src_clk(sd_card_clk), .src_rst(rst_sd), .src_value(player_fade_level),
    .dst_clk(video_clk), .dst_rst(rst_video), .dst_value(pixel_fade_level)
);
player_settings_cdc #(.WIDTH(4), .RESET_VALUE(4'd0)) u_video_osd_settings (
    .src_clk(sd_card_clk), .src_rst(rst_sd),
    .src_value({storage_error, player_auto_enabled}),
    .dst_clk(video_clk), .dst_rst(rst_video), .dst_value(video_osd_settings)
);
always @(posedge clk or posedge rst_ui) begin
    if (rst_ui) panel_volume_mode_q <= 1'b0;
    else panel_volume_mode_q <= panel_settings[8] || panel_settings[9] ||
                               panel_settings[10] || panel_settings[16] || panel_period[6];
end

// 数码管在 50 MHz 域显示已提交图片，不把按键请求当作切图成功。
always @(posedge clk or posedge rst_ui) begin
    if (rst_ui) begin
        panel_error_sync0 <= 0;
        panel_error_sync1 <= 0;
        panel_error_sync2 <= 0;
        panel_error <= 0;
        panel_state_sync0 <= 4'd0;
        panel_state_sync1 <= 4'd0;
        panel_state_sync2 <= 4'd0;
        panel_valid_sync <= 2'b00;
        panel_media_id <= 2'd0;
        panel_picture_valid <= 1'b0;
        panel_pic_event <= 1'b0;
    end else begin
        panel_error_sync0 <= storage_error != 0 ? storage_error :
                             (pixel_active_valid && (reader_underflow ||
                              reader_fifo_overflow) ? 3'd3 : 3'd0);
        panel_error_sync1 <= panel_error_sync0;
        panel_error_sync2 <= panel_error_sync1;
        if (panel_error_sync1 == panel_error_sync2) panel_error <= panel_error_sync2;
        panel_state_sync0 <= state_code;
        panel_state_sync1 <= panel_state_sync0;
        panel_state_sync2 <= panel_state_sync1;
        panel_valid_sync <= {panel_valid_sync[0], display_valid};
        panel_pic_event <= 1'b0;
        if (!panel_valid_sync[1])
            panel_picture_valid <= 1'b0;
        else if (panel_state_sync1 == panel_state_sync2 &&
                 panel_state_sync2 >= 4'd1 && panel_state_sync2 <= 6'd32) begin
            panel_media_id <= panel_state_sync2-1'b1;
            panel_picture_valid <= 1'b1;
            if (!panel_picture_valid || panel_media_id != (panel_state_sync2-1'b1))
                panel_pic_event <= 1'b1;
        end
    end
end

seg7_panel #(.IMAGE_BITS(5)) u_seg7_panel (
    .clk(clk), .rst_n(~rst_ui), .enable(1'b1),
    .error_code(panel_error),
    .picture_valid(panel_picture_valid), .media_id(panel_media_id),
    .volume(panel_settings[7:0]), .period_sec(panel_period[5:0]),
    .volume_mode(1'b0), .period_mode(1'b0),
    .fade_mode(1'b0), .fade_level(panel_settings[15:14]),
    .save_mode(1'b0), .save_status(panel_settings[13:12]),
    .auto_mode(1'b0), .auto_enabled(panel_settings[11]),
    .source_mode(1'b0),.track_mode(1'b0),
    .source_wav(1'b1),.track_number(4'd0),
    .pic_event(panel_pic_event | panel_mode_exit), .vol_event(1'b0), .prd_event(1'b0),
    .seg_n(seg_data), .dig_n(panel_dig_n)
);
// 保留原 seg_sel[0..5] 的物理引脚；新增 [6]=左2，[7]=左1。
// 面板逻辑编号 0 在最右侧，不能直接连接旧的六位排列。
assign seg_sel = {panel_dig_n[7], panel_dig_n[6], panel_dig_n[0],
                  panel_dig_n[1], panel_dig_n[2], panel_dig_n[3],
                  panel_dig_n[4], panel_dig_n[5]};

// ===================== 第八讲视频时序与帧缓存 =====================
video_timing_ctrl #(.ACTIVE_LAST(1)) video_timing_ctrl_m0 (
    .pclk(video_clk), .rst_n(~rst_video),
    .hsync(hs_0), .vsync(vs_0), .de(de_0),
    .x(video_timing_x), .y(video_timing_y)
);
// Detect the real fade start in the pixel domain; reuse the existing cue player.
// Read-bank/full-alpha changes also catch an automatic restart during a fade.
wire diagonal_cue_trigger,auto_fade_active;
reg [1:0] cue_fade_read_q;
reg cue_fade_active_q,cue_fade_full_q;
wire fade_cue_trigger=auto_fade_active && auto_fade_alpha==8'hff &&
    (!cue_fade_active_q || !cue_fade_full_q || auto_fade_read_index!=cue_fade_read_q);
always @(posedge video_clk or posedge rst_video) begin
    if(rst_video) begin cue_fade_read_q<=0;cue_fade_active_q<=0;cue_fade_full_q<=1;end
    else begin
        cue_fade_read_q<=auto_fade_read_index;cue_fade_active_q<=auto_fade_active;
        cue_fade_full_q<=auto_fade_alpha==8'hff;
    end
end
assign cue_trigger=diagonal_cue_trigger || fade_cue_trigger;
video_diagonal_control u_diagonal_control (
    .clk(video_clk),.rst(rst_video),.frame_start(video_frame_start),
    .active_valid(pixel_active_valid),.active_index(pixel_active_index),
    .auto_commit(auto_frame_commit),.selected(pixel_menu_snapshot[59]),.fade_level(pixel_fade_level),
    .active(diagonal_active),.start_pulse(diagonal_cue_trigger),.old_index(diagonal_old_index),.shift(diagonal_shift));
// The output pipeline is 20 clocks deep; wait through the front porch before
// clearing the read FIFO for the next frame.
assign video_frame_start = video_timing_x == 0 && video_timing_y == 10;
video_auto_fade_control #(.FADE_FRAMES(4)) u_auto_fade (
    .pixel_clk(video_clk), .pixel_rst(rst_video),
    .frame_start(video_frame_start), .active_valid(pixel_active_valid),
    .active_index(pixel_active_index), .auto_frame_commit(auto_frame_commit),
    .fade_level(pixel_menu_snapshot[59] ? 2'd0 : pixel_fade_level),
    .read_index(auto_fade_read_index),
    .alpha(auto_fade_alpha), .fade_active(auto_fade_active)
);
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video)
        video_read_req <= 1'b0;
    else if (video_frame_start)
        video_read_req <= 1'b1;
    else if (video_read_req_ack)
        video_read_req <= 1'b0;
end

rgb_video_adapter #(.VIDEO_DELAY(20)) rgb_video_adapter_m0 (
    .pclk(video_clk), .rst_n(~rst_video),
    .hs_in(hs_0), .vs_in(vs_0), .de_in(de_0),
    .rgb_in(video_read_data[31:8]),
    .pixel_consume(video_read_en), .video_clk(),
    .video_hs(hs), .video_vs(vs), .video_de(de),
    .video_rgb(vout_data_raw)
);

// One coherent menu/quality snapshot per video frame; the old 35 bit
// fields keep their positions. Page, row and values cannot cross independently.
always @(posedge video_clk or posedge rst_video) begin
    if(rst_video) begin frame_menu_snapshot<={1'b1,1'b0,1'b1,2'd0,2'd2,2'd2,52'h7fc0400000000};frame_thumbnail_settings<=0;end
    else if(video_frame_start) begin frame_menu_snapshot<=pixel_menu_snapshot;frame_thumbnail_settings<=pixel_thumbnail_settings;end
end
// Picture adjustment precedes the fade and both overlays; all video
// attributes follow the same two-clock processing latency.
thumbnail_overlay_24 #(.DIRECTORY_LAYOUT(1),.FULLSCREEN_THUMBNAILS(1),.ENABLE_THUMB_TRANSPARENCY(1),.FIXED_OPAQUE_THUMBNAILS(1)) u_thumbnail_overlay (
    .clk(video_clk),.rst_n(~rst_video),.hsync(hs),.vsync(vs),.de(de),
    .view_mode(frame_thumbnail_settings[19]),.thumbnail_transparency(pixel_menu_snapshot[55:54]),.pixel_x(video_x),.rgb_in(vout_data_raw),
    .frame_start(thumb_frame_start),.consume_row(thumb_consume_row),
    .display_row(thumb_display_row),.consumed_row(thumb_consumed_row),
    .pixel_address(thumb_pixel_address),.display_mask(thumb_display_mask),.pixel_data(thumb_pixel_data),
    .out_hs(thumb_hs),.out_vs(thumb_vs),.out_de(thumb_de),.out_x(thumb_x),.rgb_out(vout_data_thumbnail)
);
brightness_contrast_adjust u_picture_adjust (
    .clk(video_clk),.rst_n(~rst_video),.frame_start(video_frame_start),
    .brightness(pixel_menu_snapshot[50:43]),.contrast(pixel_menu_snapshot[42:35]),
    .in_hs(thumb_hs),.in_vs(thumb_vs),.in_de(thumb_de),.in_x(thumb_x),.rgb_in(vout_data_thumbnail),
    .out_hs(picture_hs),.out_vs(picture_vs),.out_de(picture_de),.out_x(picture_x),
    .rgb_out(vout_data_picture)
);
// 第十讲：转场处理原图，状态 OSD 保持在转场图层之上。
video_transition_pixel #(.FADE_FRAMES(4)) u_transition_pixel (
    .rgb_in(vout_data_picture), .pixel_x(picture_x),
    .alpha(auto_fade_alpha), .wipe_active(transition_wipe_active),
    .ramp(transition_ramp), .rgb_out(vout_data_transition)
);
// Diagonal edge glow removed by user choice; keep the existing pixel path.
assign vout_data_glow=vout_data_transition;
// 首图在像素域帧边界提交前保持黑屏。
osd_overlay_24 #(.OSD_X(8), .OSD_Y(8),.ENABLE_PAUSE_STATUS(1),.INDEX_BITS(5)) u_osd_overlay (
    .clk(video_clk), .rst_n(~rst_video), .vsync(picture_vs), .de(picture_de),
    .rgb_in(vout_data_glow), .pixel_x(picture_x), .enable(1'b0),
    .active_index(pixel_image_index),
    .auto_enabled(video_osd_settings[0]),
    .error_code({5'd0, video_osd_settings[3:1]}),
    .audio_status(audio_status),.audio_paused(audio_pause_ack),
    .rgb_out(vout_data_status), .de_out(), .osd_active()
);
// Course visualization under the menu; PCM tap already belongs to video_clk.
audio_progress_state u_audio_progress_state (
    .clk(video_clk),.rst_n(~rst_video),.frame_start(video_frame_start),
    .available(progress_available),.ended(wav_audio_end),.file_tag(progress_file_tag),
    .file_size(progress_file_size),.played_samples(progress_played_samples),
    .valid(progress_valid),.elapsed_bcd(progress_elapsed_bcd),.total_bcd(progress_total_bcd),
    .long_time(progress_long_time),.fill_pixels(progress_fill_pixels));
promax_audio_waveform_scanned u_audio_waveform (
    .clk(video_clk),.rst_n(~rst_video),.vsync(picture_vs),.de(picture_de),
    .rgb_in(vout_data_status),.pixel_x(picture_x),
    .enable(frame_menu_snapshot[34] && pixel_active_valid && !frame_menu_snapshot[33] &&
            (audio_status==2'd1 || audio_status==2'd2) &&
            (!pixel_source_wav || (!audio_pause_ack && !pixel_pause_requested && !audio_switch_sync[1]))),
    .pcm_tap_valid(pcm_tap_valid),.pcm_tap_left(pcm_tap_left),
    .rgb_out(vout_data_waveform),.waveform_active()
);
// The caption RAM read and ink merge add two clocks to the entire video bundle.
caption_overlay #(.ENABLE_CAPTION(1),.ENABLE_FILE_COLOR(1)) u_caption_overlay (
    .clk(video_clk),.rst_n(~rst_video),
    .in_hs(picture_hs),.in_vs(picture_vs),.in_de(picture_de),.in_x(picture_x),
    .rgb_in(pixel_active_valid ? vout_data_waveform : 24'd0),
    .visible(caption_frame_visible),.bitmap_bank(caption_frame_bank),
    .bitmap_width(caption_frame_width),.text_x(caption_frame_text_x),.color_id(caption_frame_color_id),
    .bitmap_address(caption_bitmap_address),.bitmap_read_bank(caption_bitmap_bank),.bitmap_byte(caption_bitmap_byte),
    .out_hs(caption_hs),.out_vs(caption_vs),.out_de(caption_de),.out_x(caption_x),.rgb_out(vout_data_caption)
);
always @(posedge video_clk or posedge rst_video) begin
    if(rst_video) caption_content_valid<=0;
    else caption_content_valid<={caption_content_valid[0],pixel_active_valid || caption_frame_visible};
end
screen_menu_overlay_24 #(.ENABLE_PLAY_CONTROL(1),.ENABLE_PLAY_OPTIONS(1),.ENABLE_AUDIO_VISUAL(1),.ENABLE_PICTURE_ADJUST(1),.COMPACT_MENU(1),.ENABLE_THUMBNAILS(1),.RESIDENT_THUMBNAILS(1),.DIRECTORY_LAYOUT(1),.FULLSCREEN_THUMBNAILS(1),.ENABLE_MENU_TRANSPARENCY(1),.STRONG_THUMB_BORDER(1),.DEMO_MENU(2),.ENABLE_AUDIO_IMAGE_BIND(1),.ENABLE_DIAGONAL_TRANSITION(1),.ENABLE_AUDIO_PROGRESS(1),.ENABLE_CAPTION(1),.FIXED_OPAQUE_THUMBNAILS(1),.ENABLE_SHARED_SCALING_RAM(1),.ENABLE_SW4_THUMBNAILS(1),.ENABLE_CLOCK_TIMER(1),.ENABLE_SHARED_LABEL_ROM(1),.ENABLE_LOW_POWER_MENU(1)) u_screen_menu_overlay (
    .label_request(menu_label_request),.label_address(menu_label_address),.label_grant(menu_label_grant),
    .label_response_valid(menu_label_response_valid),.label_glyph(menu_label_glyph),
    .caption_font_address(caption_font_address),.caption_font_byte(caption_font_byte),
    .clk(video_clk),.rst_n(~rst_video),.vsync(caption_vs),.de(caption_de),
    .pixel_x(caption_x),
    .image_page(pixel_picture_settings[16]),
    .brightness(pixel_picture_settings[15:8]),.contrast(pixel_picture_settings[7:0]),
    .menu_transparency(frame_menu_snapshot[53:52]),.thumbnail_transparency(frame_menu_snapshot[55:54]),
    .rgb_in(vout_data_caption),
    .caption_enabled(frame_menu_snapshot[60]),.visual_enabled(frame_menu_snapshot[34]),
    .thumbnail_view(frame_thumbnail_settings[19]),.thumbnail_waiting(frame_thumbnail_settings[20]),
    .thumbnail_focus(frame_thumbnail_settings[18:14]),.thumbnail_count(frame_thumbnail_settings[13:8]),
    .thumbnail_ready(frame_thumbnail_settings[3:0]),.thumbnail_failed(frame_thumbnail_settings[7:4]),
    .playback_mode(pixel_playback_options[1:0]),.main_keys_music(pixel_playback_options[2]),.main_keys_thumbnail(pixel_playback_options[3]),
    .menu_open(frame_menu_snapshot[33]),
    .menu_level(frame_menu_snapshot[32]),
    .menu_group(frame_menu_snapshot[31:30]),
    .menu_item({frame_menu_snapshot[56],frame_menu_snapshot[29:28]}),
    .diagonal_selected(frame_menu_snapshot[59]),.audio_image_bind(frame_menu_snapshot[57]),.progress_visible(frame_menu_snapshot[58]),
    .progress_valid(progress_valid),.progress_long_time(progress_long_time),
    .progress_elapsed_bcd(progress_elapsed_bcd),.progress_total_bcd(progress_total_bcd),.progress_fill_pixels(progress_fill_pixels),
    .auto_enabled(frame_menu_snapshot[27]),
    .source_wav(frame_menu_snapshot[26]),
    .audio_paused(audio_pause_ack),.audio_ended(wav_audio_end),
    .period_sec(frame_menu_snapshot[25:20]),
    .fade_level(frame_menu_snapshot[19:18]),
    .volume(frame_menu_snapshot[17:10]),
    .track_number(frame_menu_snapshot[9:6]),
    .track_count(frame_menu_snapshot[5:2]),
    .save_status(frame_menu_snapshot[1:0]),
    .clock_display_enabled(clock_display_enabled),.clock_stable(clock_time_stable),.clock_edit_selection(clock_edit_owner),.clock_time(clock_time),.clock_valid(clock_valid),.clock_timer(clock_timer),
    .clock_edit(clock_edit),.clock_timer_enabled(clock_timer_enabled),.clock_edit_minutes(clock_edit_minutes),
    .rgb_out(vout_data_osd),.menu_visible(pixel_menu_visible)
);
// Match the menu font BRAM's one-clock pixel latency, including closed menus.
always @(posedge video_clk or posedge rst_video) begin
    if(rst_video) begin
        menu_video_hsync<=1;menu_video_vsync<=1;menu_video_de<=0;
        menu_video_x<=0;menu_active_valid<=0;
    end else begin
        menu_video_hsync<=caption_hs;menu_video_vsync<=caption_vs;menu_video_de<=caption_de;
        menu_video_x<=caption_x;menu_active_valid<=caption_content_valid[1];
    end
end
assign vout_data = clock_sleep_frame ? 24'd0 : vout_data_osd;

media_frame_loader u_media_frame_loader (
    .mem_clk(ext_mem_clk), .rst(rst_mem),
    .Sdr_init_done(Sdr_init_done),
    .Sdr_init_ref_vld(Sdr_init_ref_vld), .Sdr_busy(Sdr_busy),
    .App_rd_busy(!memory_grant[1]), .App_wr_busy(full_write_busy),
    .App_wr_en(full_write_en), .App_wr_addr(full_write_address),
    .App_wr_din(full_write_data), .App_wr_dm(full_write_mask),.pending(full_write_pending),
    .write_clk(sd_card_clk), .write_req(sd_card_write_req),
    .write_req_ack(full_write_ack),
    .write_finish(full_write_finish),
    .write_addr_index(write_buf_idx), .write_len(FRAME_PIXELS[ADDR_BITS-1:0]),
    .write_en(sd_card_write_en), .write_data(sd_card_write_data),
    .fifo_overflow(full_writer_overflow),.write_ready(full_writer_ready)
);

media_frame_reader #(.ENABLE_DIAGONAL_TRANSITION(1),.ENABLE_WIPE(0),.BURST_SIZE(128)) u_media_frame_reader (
    .mem_clk(ext_mem_clk), .rst(rst_mem),
    .Sdr_init_done(Sdr_init_done),
    .Sdr_init_ref_vld(Sdr_init_ref_vld), .Sdr_busy(Sdr_busy),
    .Sdr_rd_en(Sdr_rd_en && memory_grant[0]), .Sdr_rd_dout(Sdr_rd_dout),
    .App_wr_busy(!memory_grant[0]), .App_rd_busy(full_read_busy),
    .App_rd_en(full_read_en), .App_rd_addr(full_read_address),.pending(full_read_pending),
    .read_clk(video_clk), .read_req(video_read_req),
    .read_req_ack(video_read_req_ack), .read_finish(),
    .read_addr_index(auto_fade_read_index), .read_len(FRAME_PIXELS[ADDR_BITS-1:0]),
    .diagonal_active(diagonal_active),.diagonal_old_index(diagonal_old_index),
    .diagonal_new_index(pixel_active_index),.diagonal_shift(diagonal_shift),
    .wipe_active(1'b0),
    .wipe_old_index(2'd0),
    .wipe_new_index(2'd0),
    .wipe_boundary(10'd0),
    .read_en(video_read_en), .read_data(video_read_data),
    .underflow(reader_underflow),
    .fifo_overflow(reader_fifo_overflow)
);

assign writer_fifo_overflow=full_writer_overflow || small_writer_overflow;
assign App_wr_busy=full_write_busy || small_write_busy;
assign App_rd_busy=full_read_busy || small_read_busy;
assign App_wr_en=(memory_grant[1] && full_write_en) || (memory_grant[2] && small_write_en);
assign App_wr_addr=memory_grant[2] ? small_write_address : full_write_address;
assign App_wr_din=memory_grant[2] ? small_write_data : full_write_data;
assign App_wr_dm=4'b0000;
assign App_rd_en=(memory_grant[0] && full_read_en) || (memory_grant[3] && small_read_en);
assign App_rd_addr=memory_grant[3] ? small_read_address : full_read_address;
media_memory_arbiter u_memory_arbiter (
    .clk(ext_mem_clk),.rst(rst_mem),.initialized(Sdr_init_done),
    .controller_busy(Sdr_busy),.refresh_busy(Sdr_init_ref_vld),
    .request({small_read_pending,small_write_pending,full_write_pending,
                full_read_pending}),
    .busy({small_read_busy,small_write_busy,full_write_busy,full_read_busy}),.grant(memory_grant)
);
thumbnail_capture #(.ENABLE_AREA_AVERAGE(1)) u_thumbnail_capture (
    .write_clk(sd_card_clk),.write_rst(rst_sd),.mem_clk(ext_mem_clk),.mem_rst(rst_mem),
    .write_req(sd_card_write_req),.image_index(thumbnail_load_index),.load_active(thumbnail_load_active),
    .pixel_valid(sd_card_write_en),.pixel_data(sd_card_write_data),
    .full_write_ack(full_write_ack),.full_write_finish(full_write_finish),
    .publish_toggle(thumbnail_publish_toggle),.publish_index(thumbnail_publish_index),
    .invalidate_toggle(thumbnail_invalidate_toggle),
    .combined_ack(sd_card_write_req_ack),.combined_finish(frame_write_finish),
    .ready_mask(thumbnail_ready_mem),.overflow(small_writer_overflow),.pixel_ready(thumbnail_pixel_ready),
    .initialized(Sdr_init_done),.controller_busy(Sdr_busy),.refresh_busy(Sdr_init_ref_vld),.grant(memory_grant[2]),
    .pending(small_write_pending),.busy(small_write_busy),.app_write(small_write_en),
    .app_address(small_write_address),.app_data(small_write_data)
);
thumbnail_reader #(.DIRECTORY_LAYOUT(1),.ENABLE_PREVIEW(0)) u_thumbnail_reader (
    .mem_clk(ext_mem_clk),.mem_rst(rst_mem),.pixel_clk(video_clk),.pixel_rst(rst_video),
    .view_mode(frame_thumbnail_settings[19]),.frame_start(thumb_frame_start),
    .page_index(frame_thumbnail_settings[18:16]),
    .focus_slot(frame_thumbnail_settings[15:14]),
    .thumbnail_ready(frame_thumbnail_settings[3:0] & ~frame_thumbnail_settings[7:4]),
    .consume_row(thumb_consume_row),.consumed_row(thumb_consumed_row),.display_row(thumb_display_row),
    .pixel_address(thumb_pixel_address),.pixel_data(thumb_pixel_data),.display_mask(thumb_display_mask),
    .initialized(Sdr_init_done),.controller_busy(Sdr_busy),.refresh_busy(Sdr_init_ref_vld),.grant(memory_grant[3]),
    .return_valid(Sdr_rd_en && memory_grant[3]),.return_data(Sdr_rd_dout),
    .pending(small_read_pending),.busy(small_read_busy),.app_read(small_read_en),.app_address(small_read_address)
);
sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== 第四讲：音视频联动与参考 HDMI 编码链路 =====================
media_audio_video_control #(
    .VOLUME(AUDIO_VOLUME),.STATE_BITS(6),.MAX_IMAGES(32)
) u_media_audio_video_control (
    .pixel_clk(video_clk),
    .rst(rst_video),
    .video_hsync(hs),
    .video_vsync(vs),
    .state_code(state_code),
    .display_valid(display_valid),
    .video_x(video_x),
    .timing_locked(video_timing_locked),
    .media_id(media_id),
    .volume(audio_volume),.image_index(pixel_image_index)
);

media_hdmi_audio_bridge #(.BLIP_SAMPLES(0),.ENABLE_WAV_TRANSPORT(1),.ENABLE_TRANSITION_CUE(1),.ENABLE_OUTPUT_MUTE(1)) u_media_hdmi_audio_bridge (
    .output_mute(clock_sleep),
    .pixel_clk(video_clk),
    .pixel_rst_n(~rst_video & video_timing_locked),
    .video_hsync(menu_video_hsync),
    .video_vsync(menu_video_vsync),
    .video_de(menu_video_de),
    .video_x(menu_video_x),
    .video_rgb(vout_data),
    .media_id(media_id),
    .volume(audio_volume != 0 ? pixel_volume : 8'd0),
    .cue_sample(cue_sample),.cue_valid(cue_valid),.cue_ready(cue_ready),
    .wav_valid(wav_sample_valid),
    .wav_ready(wav_sample_ready),
    .wav_left(wav_sample_left),
    .wav_right(wav_sample_right),
    .wav_active(wav_audio_active),
    .wav_end(wav_audio_end),.wav_paused(pixel_pause_requested),
    .force_arpeggio(!pixel_source_wav),
    .audio_switching(audio_switch_sync[1]),
    .audio_status(audio_status),
    .audio_switch_ready(audio_switch_ready),.audio_pause_ack(audio_pause_ack),
    .channel0_symbol(tmds_ch0_data),
    .channel1_symbol(tmds_ch1_data),
    .channel2_symbol(tmds_ch2_data),
    .sequence_error(sequence_error),
    .tone_overflow(tone_overflow),
    .pcm_contract_error(pcm_contract_error),
    .blip_active(blip_active),
    .pcm_tap_valid(pcm_tap_valid),
    .pcm_tap_left(pcm_tap_left)
);

// 固定 640x480/25 MHz 输出；参考编码链路不包含 EDID/DDC 主机。
assign HDMI_DDC_SCL = 1'b1;
assign HDMI_DDC_SDA = 1'bz;
assign tmds_clk_data = 10'b1111100000;

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_serial),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
