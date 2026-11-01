// TF 卡图片控制：扫描 -> 四bank加载 -> 帧边界提交显示
// 实体 KEY2 加/下一张，KEY3 减/上一张，KEY4 切换自动/音量/周期/保存页面。
// 图片编号 0~3，每张图片固定占用同编号SDRAM缓存。
module sd_card_bmp #(
        parameter integer CLK_FREQ_HZ       = 100_000_000,  // 时钟频率（Hz）
        parameter [31:0]  SCAN_START_SECTOR = 32'd0,  // 旧接口兼容参数，FAT32不使用
        parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,  // 旧接口兼容参数，FAT32不使用
        parameter [2:0]   SCAN_TARGET_COUNT = 3'd4,  // 旧接口兼容参数；当前固定匹配PIC1～4
        // 按键长按和轮播时间
        parameter integer LONG_PRESS_MS      = 500,  // 长按时间（ms）
        parameter integer SD_READ_TIMEOUT_MS = 500,
        parameter integer LOAD_TIMEOUT_MS = 3000,
        parameter integer REINIT_TIMEOUT_MS = 2000,
        parameter integer MAX_RETRIES = 1,
        parameter integer AUTO_PLAY_MS       = 3000, // 自动轮播等待时间（ms，不含加载时间）
        parameter integer TRANSITION_FRAMES  = 0,    // 0保留原硬切；正式顶层启用转场
        parameter [31:0] AUDIO_START_LBA     = 32'd0,
        parameter [31:0] AUDIO_TOTAL_SECTORS = 32'd0,
        parameter integer AUDIO_AUTO_FILES   = 0,
        parameter integer ENABLE_AUDIO_CONTROL = 0,
        parameter integer ENABLE_PLAY_OPTIONS = 0,
        parameter integer MAX_IMAGES = 4,
        parameter integer IMAGE_BITS = $clog2(MAX_IMAGES),
        parameter integer USE_SCREEN_MENU    = 0,
        parameter integer SCREEN_MENU_TIMEOUT_MS = 10000,
        parameter integer ENABLE_AUDIO_VISUAL = 0,
        parameter integer ENABLE_PICTURE_ADJUST = 0,
        parameter integer ENABLE_THUMBNAILS = 0,
        parameter integer RESIDENT_THUMBNAILS = 0,
        parameter integer FULLSCREEN_THUMBNAILS = 0,
        parameter integer ENABLE_MENU_TRANSPARENCY = 0,
        parameter integer ENABLE_CONFIRM_KEY = 0,
        parameter integer ENABLE_SWITCH_MODE = 0,
        parameter integer DEMO_MENU = 0,
        parameter integer ENABLE_THUMB_TRANSPARENCY = 0,
        parameter integer ENABLE_TRANSITION_CUE=0,
        parameter integer ENABLE_DIAGONAL_TRANSITION=0,
        parameter integer ENABLE_CAPTION=0,
        parameter integer ENABLE_ADAPTIVE_SCALING=0,
        parameter integer FIXED_OPAQUE_THUMBNAILS=0,
    parameter integer ENABLE_AUDIO_PROGRESS = 0,
    parameter integer ENABLE_AUDIO_IMAGE_BIND = 0,
        parameter integer MENU_ITEM_BITS = (ENABLE_AUDIO_IMAGE_BIND!=0 || ENABLE_AUDIO_PROGRESS!=0 || ENABLE_CAPTION!=0) ? 3 : 2,
        parameter integer ENABLE_SHARED_SCALING_RAM=0,
        parameter integer ENABLE_SW4_THUMBNAILS=0,
        parameter integer ENABLE_FULL_CONFIG_SAVE=0,
        parameter integer ENABLE_CLOCK_TIMER=0,
        parameter integer ENABLE_LOW_POWER_MENU=0
    )(
        input                       clk,  // 时钟
        input                       startup_ready, // synchronized SDRAM initialization complete
        input                       rst,  // 高电平异步复位
        input                       key_next,  // 实体 KEY2（B2）
        input                       key_auto,  // 实体 KEY4（C1），保留原端口名
        input                       key_confirm, // KEY1/A2, active low
        input [1:0]                 main_keys_sw, // {SW2,SW3}
        input                       key_prev,  // 实体 KEY3（B1）
        input                       period_cfg_valid,  // 后续菜单使用，当前顶层固定为0
        input [31:0]                period_cfg_cycles,
        output [7:0]                volume,
        output                      volume_mode,
        output                      fade_mode,
        output [1:0]                fade_level,
        output                      period_mode,
        output [5:0]                period_seconds,
        output                      save_mode,
        output                      auto_mode,
        output                      auto_enabled,
        output                      source_mode,
        output                      track_mode,
        output                      source_wav,
        output                      audio_paused,
        output [1:0]                playback_mode,
        output                      main_keys_music,
        output                      main_keys_thumbnail,
        output                      menu_open,
        output                      menu_level,
        output [1:0]                menu_group,
        output [MENU_ITEM_BITS-1:0] menu_item,
        input wire cue_trigger,cue_sample_ready,
        output wire signed [15:0] cue_sample,
        output wire cue_sample_valid,
        output diagonal_selected,
        output                      audio_image_bind,
        output                      progress_visible,
        output [3:0]                progress_file_tag,
        output [31:0]               progress_file_size,progress_played_samples,
        output                      progress_available,
        output [1:0]                menu_transparency,
        output [1:0]                thumbnail_transparency,
        output [3:0]                track_number,
        output [3:0]                track_count,
        output [1:0]                save_status,
        input                       flash_miso,
        output                      flash_cs_n, flash_sclk, flash_mosi, flash_wp_n, flash_hold_n,
        input  [15:0]               bmp_width,  // 目标图片宽度（用于匹配 BMP 文件头）
        input wire                  write_ready,
        input  [15:0]               bmp_height,  // 目标图片高度（用于匹配 BMP 文件头）
        output reg                  display_valid,  // 图片可显示标志（首帧提交后保持高；复位、卡未初始化或启动扫描时清零）
        //output      [3:0]           state_code,
        output reg [2:0]            error_code, // 0 OK, 1 header, 2 timeout, 3 truncated, 4 no image
        output reg [IMAGE_BITS:0]   state_code,  // 数码管图片编号（初始化后输出 img_idx + 1，不是 BMP 状态码）

        input                       write_finish_toggle,  // 整帧写完翻转标志（每写完一帧翻转并保持至下次写完；复位清零）
        output reg [1:0]            write_buf_idx,  // 写缓冲区编号
        output reg [1:0]            disp_buf_idx,  // 提交显示的缓冲区编号
        output reg [MAX_IMAGES-1:0] image_complete,  // 四张图片的SDRAM缓存有效标记
        output                      frame_commit_request_toggle,
        output [1:0]                frame_commit_request_index,
        output                      frame_commit_acknowledge_toggle,
        output reg                  auto_frame_commit,
        input                       pixel_clk, pixel_rst, frame_start,
        output [1:0]                active_index,
        output                      active_valid,
        output [7:0]                transition_alpha,
        output                      transition_wipe_active,
        output [4:0]                transition_ramp,
        input                       write_fifo_overflow,

        output                      write_req,  // 整帧写请求
        input                       write_req_ack,  // 写请求应答
        output                      write_en,  // FIFO 写使能（不是写 TF 卡）
        output [31:0]               write_data,  // 写数据（高 24 位 RGB，低 8 位补零）
        output                      audio_sample_valid,
        input                       audio_sample_ready,
        output signed [15:0]        audio_sample_left,
        output signed [15:0]        audio_sample_right,
        output                      audio_active,
        output                      audio_end,
        output                      audio_switching,
        input                       audio_switch_ready,
        output                      SD_nCS,  // SPI 片选（低有效）
        output                      SD_DCLK,  // SPI 时钟
        output                      SD_MOSI,  // SPI 主发从收
        input                       SD_MISO,  // SPI 主收从发
        output                      visual_enabled,
        output                      image_page,
        output [7:0]                brightness,contrast,
        input [31:0]                thumbnail_ready,
        output                      thumbnail_view,thumbnail_waiting,thumbnail_load_active,
        output [4:0]                thumbnail_focus,thumbnail_load_index,
        output [5:0]                thumbnail_image_count,
        output [31:0]               thumbnail_failed,
        output reg                  thumbnail_publish_toggle,thumbnail_invalidate_toggle,
        output wire caption_enabled,
        input wire caption_pixel_enabled,caption_pixel_menu_open,caption_pixel_source_wav,
        input wire [11:0] caption_bitmap_address,
        input wire caption_bitmap_bank,
        output wire [7:0] caption_bitmap_byte,
        output wire caption_frame_visible,caption_frame_bank,
        output wire [9:0] caption_frame_width,
        output wire [2:0] caption_frame_color_id,
        output wire signed [11:0] caption_frame_text_x,
        output reg [4:0]            thumbnail_publish_index,
    output wire [8:0] bmp_buffer_address,
    output wire bmp_buffer_write,
    output wire [7:0] bmp_buffer_write_data,
    input wire [7:0] bmp_buffer_read_data,
    input wire thumbnail_switch,
    input wire display_sleep,
    output wire [2:0] clock_command
);

    localparam integer LOAD_CYCLES = (CLK_FREQ_HZ / 1000) * LOAD_TIMEOUT_MS;
    localparam integer REINIT_CYCLES = (CLK_FREQ_HZ / 1000) * REINIT_TIMEOUT_MS;
    wire [2:0] bmp_error;
    wire bmp_load_error, bmp_load_done, bmp_scan_error, bmp_scan_reject, bmp_sd_recover;
    reg [2:0] write_ack_sync;
    reg write_started, ack_seen_low;
    (* max_fanout=8 *) reg [MAX_IMAGES-1:0] failed_images;
    reg [7:0] retry_count, scan_retry_count;
    reg recovery_pending, recovery_blocked, recovery_scan, retry_pending;
    reg [31:0] recovery_count, init_wait_count;
    reg [3:0] sd_reset_count;
    wire transport_reset = rst || sd_reset_count != 0;
    wire [IMAGE_BITS:0] usable_next, usable_prev, usable_first;
    wire thumb_enter,thumb_next,thumb_prev,thumb_confirm,thumb_back,thumb_select_event;
    wire [4:0] thumb_target;
    reg thumb_select_pending,thumbnail_flush_pending;
    reg [IMAGE_BITS-1:0] thumb_selected_image;
    wire thumb_selection_done;
    wire key_next_press;  // 图片模式：实体 KEY2 短按事件
    wire key_auto_press;  // 自动轮播菜单：实体 KEY2/KEY3 的明确开关事件
    wire key_auto_value;
    wire track_next_event,track_prev_event,track_change,replay_event;
    reg [1:0] playback_end_sync;
    always @(posedge clk or posedge rst) begin
        if(rst) playback_end_sync<=0;
        else playback_end_sync<={playback_end_sync[0],audio_end};
    end
    wire [2:0] selected_track;
    wire [31:0] selected_audio_cluster,selected_audio_size;
    wire audio_catalog_ready;
    wire caption_found_valid,caption_request,caption_transport_recover;
    wire [63:0] caption_found_name,caption_lookup_name;
    wire [31:0] caption_found_cluster,caption_found_size,caption_address;
    wire caption_lookup_valid;
    reg [63:0] caption_audio_name;
    reg caption_audio_name_valid;
    reg [3:0] caption_audio_tag;
    wire [31:0] caption_audio_size;
    wire audio_found_valid;
    wire [87:0] audio_found_name;
    wire [31:0] audio_found_cluster,audio_found_size;
    wire [7:0] audio_spc;
    wire [31:0] audio_fat_lba,audio_data_lba,audio_max_cluster;
    assign track_number = track_count == 0 ? 4'd0 : {1'b0,selected_track}+4'd1;

    wire [31:0] scan_found_size;
    reg [31:0] img_size0,img_size1,img_size2,img_size3,load_file_size;
    wire             bmp_sd_sec_read;  // BMP 扇区读请求
    wire [31:0]      bmp_sd_sec_read_addr;
    wire [7:0]       card_sd_sec_read_data;
    wire             card_sd_sec_read_data_valid;
    wire             card_sd_sec_read_end;
    wire             wav_sd_sec_read;
    wire [31:0]      wav_sd_sec_read_addr;
    wire             wav_sector_busy, wav_sector_done, wav_sector_valid;
    wire [7:0]       wav_sector_byte, wav_sector_error;
    wire [8:0]       wav_sector_byte_index;
    wire             audio_play_enable;
    reg              audio_started;
    reg [24:0]       audio_rate_accumulator;
    wire             audio_sample_tick = audio_rate_accumulator >= (25_000_000 - 48_000);
    reg sector_granted,sector_audio_owner,sector_cue_owner,sector_caption_owner,caption_last_grant;
    wire preload_preempt_pending;
    wire caption_owned=ENABLE_CAPTION!=0 && sector_granted && sector_caption_owner;
    wire cue_request;wire [31:0] cue_address;
    wire cue_owned=ENABLE_TRANSITION_CUE!=0 && sector_granted && sector_cue_owner;
    wire cue_file_match=ENABLE_TRANSITION_CUE!=0 && audio_found_name=="TRANS   PCM";
    wire bmp_sector_owner=MAX_IMAGES>4 ? sector_granted && !sector_audio_owner && !sector_cue_owner && !sector_caption_owner : !audio_started;
    wire audio_sector_owner=MAX_IMAGES>4 ? sector_granted && sector_audio_owner : audio_started;
    wire sd_sec_read=MAX_IMAGES>4 ? sector_granted &&
        (sector_caption_owner ? caption_request : sector_cue_owner ? cue_request : sector_audio_owner ? wav_sd_sec_read : bmp_sd_sec_read) :
        audio_started ? wav_sd_sec_read : bmp_sd_sec_read;
    wire [31:0] sd_sec_read_addr=MAX_IMAGES>4 ?
        (sector_caption_owner ? caption_address : sector_cue_owner ? cue_address : sector_audio_owner ? wav_sd_sec_read_addr : bmp_sd_sec_read_addr) :
        audio_started ? wav_sd_sec_read_addr : bmp_sd_sec_read_addr;
    // An entire physical sector has one owner; queued audio has priority.
    always @(posedge clk or posedge rst) begin
        if(rst) begin sector_granted<=0;sector_audio_owner<=0;sector_cue_owner<=0;sector_caption_owner<=0;caption_last_grant<=0;end
        else if(transport_reset || !sd_init_done) sector_granted<=0;
        else if(sector_granted) begin
            if(card_sd_sec_read_end) sector_granted<=0;
        end else if(wav_sd_sec_read && audio_started) begin
            sector_granted<=1;sector_audio_owner<=1;sector_cue_owner<=0;sector_caption_owner<=0;
        end else if(ENABLE_TRANSITION_CUE!=0 && cue_request) begin
            sector_granted<=1;sector_audio_owner<=0;sector_cue_owner<=1;sector_caption_owner<=0;
        end else if(ENABLE_CAPTION!=0 && caption_request && (!bmp_sd_sec_read || !caption_last_grant)) begin
            sector_granted<=1;sector_audio_owner<=0;sector_cue_owner<=0;sector_caption_owner<=1;caption_last_grant<=1;
        end else if(bmp_sd_sec_read && !preload_preempt_pending) begin
            sector_granted<=1;sector_audio_owner<=0;sector_cue_owner<=0;sector_caption_owner<=0;caption_last_grant<=0;
        end
    end
    assign audio_play_enable = audio_started;
    assign audio_active = wav_stream_active;
    assign audio_end = wav_stream_end;

    always @(posedge clk or posedge rst) begin
        if (rst)
            audio_started <= 1'b0;
        else if (!audio_started &&
                 ((AUDIO_AUTO_FILES != 0 && track_count != 0 && audio_catalog_ready) ||
                  (AUDIO_AUTO_FILES == 0 && AUDIO_START_LBA != 0 &&
                   AUDIO_TOTAL_SECTORS != 0)) && display_valid &&
                 scan_done && selection_ready && bmp_ready && !load_busy &&
                 !load_start_pulse && !scan_start_pulse && !bmp_sd_sec_read &&
                 !recovery_pending && !recovery_blocked && !transport_reset &&
                 img_found_count!=0 &&
                 (MAX_IMAGES>4 || ((image_complete & ((4'b0001 << img_found_count)-1'b1)) ==
                  ((4'b0001 << img_found_count)-1'b1))))
            audio_started <= 1'b1;
    end

    always @(posedge pixel_clk or posedge pixel_rst) begin
        if (pixel_rst)
            audio_rate_accumulator <= 25'd0;
        else if (audio_sample_tick)
            audio_rate_accumulator <= audio_rate_accumulator + 48_000 - 25_000_000;
        else
            audio_rate_accumulator <= audio_rate_accumulator + 48_000;
    end
    wire [3:0]       state_code_i;  // BMP 模块状态码（当前未用于数码管显示）
    wire             bmp_data_wr_en;  // 像素写使能
    wire [23:0]      bmp_data;  // RGB 像素数据
    wire             sd_init_done;  // SD 卡初始化完成标志
    wire             bmp_ready;  // BMP 模块空闲标志（不代表 SDRAM 已写完）
    reg scan_ready_for_load;
    always @(posedge clk or posedge rst) begin
        if(rst) scan_ready_for_load<=0;
        else scan_ready_for_load<=scan_done && !scan_found_valid && !scan_start_pulse;
    end
    wire             scan_done;  // 扫描完成标志（结束后保持高，新扫描或初始化时清零）
    wire             scan_found_valid;  // 找到匹配图片的脉冲
    wire [31:0]      scan_found_sector;  // 首簇号（保留旧信号名）
    wire [IMAGE_BITS:0] scan_found_total;  // 找到的图片总数（此处未参与调度）

    reg              scan_start_pulse;  // 扫描启动脉冲
    reg              load_start_pulse;  // 加载启动脉冲
    reg [31:0]       load_sector;  // 加载图片首簇号（保留旧信号名）
    reg              scan_kicked;  // 扫描已启动标志
    reg              first_image_committed;  // 首图已提交显示标志
    wire             auto_play_en;  // 自动播放使能
    assign auto_enabled = auto_play_en;
    wire [31:0]      auto_cnt;  // 自动播放等待计数
    wire [31:0]      auto_play_cycles;
    reg [IMAGE_BITS:0] img_found_count;  // 本地图片计数
    reg [IMAGE_BITS-1:0] img_idx;  // 已提交显示的图片编号
    reg [IMAGE_BITS-1:0] load_idx;  // 加载图片编号
    reg              request_commit;
    reg [1:0]        request_commit_index;
    reg              frame_commit_ack_seen;
    wire             frame_commit_done = frame_commit_acknowledge_toggle != frame_commit_ack_seen;
    wire             frame_commit_pending = frame_commit_request_toggle != frame_commit_acknowledge_toggle;
    wire [1:0] pending_buf_idx = frame_commit_request_index;
    reg [31:0]       img_sector0;  // 图片 0 起始扇区
    reg [31:0]       img_sector1;  // 图片 1 起始扇区
    reg [31:0]       img_sector2;  // 图片 2 起始扇区
    reg [31:0]       img_sector3;  // 图片 3 起始扇区
    wire             next_req_pending;  // 下一张待处理标志
    reg              load_busy;  // 加载忙标志（包含等待 SDRAM 写完）
    reg preload_background;
    reg [5:0] preload_release_count;
    reg [31:0]       load_timeout_cnt;  // 加载超时计数
    reg              load_timeout_expired;
    localparam integer SCALING_BASE_SECONDS=(LOAD_TIMEOUT_MS+999)/1000;
    localparam integer SCALING_SECONDS_BITS=$clog2(SCALING_BASE_SECONDS+65);
    reg [SCALING_SECONDS_BITS-1:0] scaling_elapsed_seconds;
    //Default3 seconds plus1 second per started256KiB; preserves test timeout overrides.
    wire [SCALING_SECONDS_BITS-1:0] scaling_timeout_seconds=SCALING_BASE_SECONDS+load_file_size[24:18]+(|load_file_size[17:0]);
    reg              load_abort;  // 中止当前 BMP 请求，失败缓冲区不提交

    // 实体 KEY3 短按上一张
    wire        key_prev_press;  // 图片模式：实体 KEY3 短按事件
    wire        prev_req_pending;  // 上一张待处理标志
    reg         clear_play_requests;
    reg         stop_playback;
    reg         reset_play_timer;
    reg         retry_next_event;
    reg         auto_nav_pending;
    reg         manual_nav_pending;
    // Capture picture-key intent separately from thumbnail confirmation.
    reg picture_nav_cue_pending,manual_commit_cue,manual_cue_toggle;

    // 分别记录 BMP 空闲和 SDRAM 写完，两个条件齐备后提交显示
    reg              source_done_seen;  // BMP 空闲记录（加载忙时检测到 bmp_ready 后置位）
    reg              write_done_seen;  // 整帧写完记录（保存完成脉冲，提交、超时或新任务时清零）

    // 同步存储时钟域的写完成通知
    reg [2:0]        wrfin_tgl_sync;  // 写完成翻转信号同步寄存器
    wire             write_finish_pulse;  // 整帧写完脉冲

    wire auto_tick_raw;
    wire auto_tick=auto_tick_raw && !(ENABLE_AUDIO_IMAGE_BIND!=0 && audio_image_bind);  // 轮播计时到达标志
    wire key_period_changed;
    reg [IMAGE_BITS-1:0] pending_image;
    wire binding_pending,bound_allowed_pixel,frame_commit_applied,binding_metadata_ready;
    wire [IMAGE_BITS-1:0] binding_target;
    wire [2:0] bound_track_pixel;
    wire [3:0] binding_file_tag;
    wire binding_stream_reset_pixel,binding_sample_started;
    reg commit_is_bound;
    reg audio_image_bind_q;
    wire binding_changed=ENABLE_AUDIO_IMAGE_BIND!=0 && audio_image_bind_q!=audio_image_bind;
    always @(posedge clk or posedge rst) begin
        if(rst) audio_image_bind_q<=0;else audio_image_bind_q<=audio_image_bind;
    end
    wire binding_navigation=binding_pending && !key_next_press && !key_prev_press && !thumb_select_event;
    wire requested_is_bound=ENABLE_AUDIO_IMAGE_BIND!=0 && binding_navigation && first_image_committed &&
        !thumb_select_pending && !next_req_pending && !prev_req_pending;
    generate if(ENABLE_AUDIO_IMAGE_BIND!=0) begin : g_audio_image_bind
        audio_image_binding #(.IMAGE_BITS(IMAGE_BITS)) binding_control (
            .clk(clk),.rst(rst),.pixel_clk(pixel_clk),.pixel_rst(pixel_rst),
            .file_tag(binding_file_tag),.stream_reset_pixel(binding_stream_reset_pixel),.sample_started(binding_sample_started),
            .enabled(audio_image_bind && auto_play_en && source_wav && !recovery_blocked),
            .manual_event(key_next_press || key_prev_press || thumb_select_event),
            .submitted(request_commit && commit_is_bound),.submitted_target(pending_image),.image_count(img_found_count),
            .failed_images(failed_images),.current_image(img_idx),.pending(binding_pending),.target(binding_target),
            .metadata_ready(binding_metadata_ready),.allowed_pixel(bound_allowed_pixel),.track_pixel(bound_track_pixel));
    end else begin : g_no_audio_image_bind
        assign binding_pending=0;assign binding_target=0;assign bound_allowed_pixel=0;assign bound_track_pixel=0;assign binding_metadata_ready=1;
    end endgenerate

    wire [IMAGE_BITS-1:0] requested_image = ENABLE_THUMBNAILS!=0 && thumb_select_pending ? thumb_selected_image : !first_image_committed ? usable_first[IMAGE_BITS-1:0] :
                                 next_req_pending ? usable_next[IMAGE_BITS-1:0] :
                                 prev_req_pending ? usable_prev[IMAGE_BITS-1:0] :
                                 binding_navigation ? binding_target : usable_next[IMAGE_BITS-1:0];

    assign write_en   = bmp_data_wr_en && load_busy && write_started && !bmp_load_error && !load_abort;  // 像素有效时写 FIFO

    assign write_data = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};  // RGB 低位补零为 32 位

    //assign auto_tick  = (auto_cnt == (CLK_FREQ_HZ - 1));// 1s计数

    assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];  // 检测同步后的翻转，生成单拍脉冲

    //assign state_code = state_code_i;//状态码输出

    wire save_event, save_busy, restore_valid, restore_period_valid;
    wire restore_auto_valid, restore_auto_enabled;
    wire restore_diagonal;
    wire [1:0] restore_fade_level,restore_playback_mode;
    wire restore_main_keys_music,restore_main_keys_thumbnail,restore_audio_image_bind,restore_progress_visible;
    wire [1:0] restore_thumbnail_transparency;
    wire [1:0] restore_menu_transparency;
    reg eof_seen,auto_track_next,auto_replay;
    always @(posedge clk or posedge rst) begin
        if(rst) begin eof_seen<=0;auto_track_next<=0;auto_replay<=0;end
        else begin
            auto_track_next<=0;auto_replay<=0;
            if(!playback_end_sync[1]) eof_seen<=0;
            else if(!eof_seen) begin
                eof_seen<=1;
                if(ENABLE_PLAY_OPTIONS!=0 && source_wav && !audio_paused &&
                   audio_started && track_count!=0 && !track_change &&
                   !track_next_event && !track_prev_event && !replay_event) begin
                    if(playback_mode==1) auto_replay<=1;
                    else if(playback_mode==2) auto_track_next<=1;
                end
            end
        end
    end
    wire [7:0] restore_volume;
    wire [23:0] restore_ui;
    wire [5:0] restore_period_sec;
    player_volume_store #(.CLK_HZ(CLK_FREQ_HZ),.ENABLE_FULL_CONFIG_SAVE(ENABLE_FULL_CONFIG_SAVE),.ENABLE_PLAY_OPTIONS(ENABLE_PLAY_OPTIONS),.ENABLE_MENU_TRANSPARENCY(ENABLE_MENU_TRANSPARENCY),.ENABLE_THUMB_TRANSPARENCY(ENABLE_THUMB_TRANSPARENCY),.ENABLE_AUDIO_IMAGE_BIND(ENABLE_AUDIO_IMAGE_BIND),.ENABLE_DIAGONAL_TRANSITION(ENABLE_DIAGONAL_TRANSITION),.ENABLE_AUDIO_PROGRESS(ENABLE_AUDIO_PROGRESS)) u_volume_store (
        .clk(clk), .rst(rst), .save_mode(save_mode), .save_event(save_event),
        .volume(volume), .period_sec(period_seconds),
        .brightness(brightness),.contrast(contrast),.visual_enabled(visual_enabled),.caption_enabled(caption_enabled),.source_wav(source_wav),.restore_ui(restore_ui),
        .diagonal_selected(diagonal_selected),.restore_diagonal(restore_diagonal),
        .auto_enabled(auto_play_en), .fade_level(fade_level),
        .playback_mode(playback_mode),.main_keys_music(main_keys_music),.main_keys_thumbnail(ENABLE_SW4_THUMBNAILS!=0 && ENABLE_FULL_CONFIG_SAVE==0 ? 1'b0 : main_keys_thumbnail),.menu_transparency(menu_transparency),.thumbnail_transparency(ENABLE_SW4_THUMBNAILS!=0 ? 2'd0 : thumbnail_transparency),.audio_image_bind(audio_image_bind),.progress_visible(progress_visible),
        .restore_valid(restore_valid), .restore_volume(restore_volume),
        .restore_period_valid(restore_period_valid), .restore_period_sec(restore_period_sec),
        .restore_auto_valid(restore_auto_valid),
        .restore_auto_enabled(restore_auto_enabled),
        .restore_fade_level(restore_fade_level),
        .restore_playback_mode(restore_playback_mode),.restore_main_keys_music(restore_main_keys_music),.restore_menu_transparency(restore_menu_transparency),.restore_thumbnail_transparency(restore_thumbnail_transparency),.restore_main_keys_thumbnail(restore_main_keys_thumbnail),.restore_audio_image_bind(restore_audio_image_bind),.restore_progress_visible(restore_progress_visible),
        .save_busy(save_busy), .save_status(save_status),
        .flash_miso(flash_miso), .flash_cs_n(flash_cs_n), .flash_sclk(flash_sclk),
        .flash_mosi(flash_mosi), .flash_wp_n(flash_wp_n), .flash_hold_n(flash_hold_n)
    );
    generate if (USE_SCREEN_MENU != 0) begin : g_screen_menu_keys
    screen_menu_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),.LONG_PRESS_MS(LONG_PRESS_MS),
        .MENU_TIMEOUT_MS(SCREEN_MENU_TIMEOUT_MS),.ENABLE_CAPTION(ENABLE_CAPTION),.FIXED_OPAQUE_THUMBNAILS(FIXED_OPAQUE_THUMBNAILS),
        .ENABLE_PLAY_CONTROL(ENABLE_AUDIO_CONTROL),.ENABLE_PLAY_OPTIONS(ENABLE_PLAY_OPTIONS),
        .ENABLE_AUDIO_VISUAL(ENABLE_AUDIO_VISUAL),.ENABLE_PICTURE_ADJUST(ENABLE_PICTURE_ADJUST),.ENABLE_THUMBNAILS(ENABLE_THUMBNAILS),.RESIDENT_THUMBNAILS(RESIDENT_THUMBNAILS),.FULLSCREEN_THUMBNAILS(FULLSCREEN_THUMBNAILS),.ENABLE_MENU_TRANSPARENCY(ENABLE_MENU_TRANSPARENCY),.ENABLE_CONFIRM_KEY(ENABLE_CONFIRM_KEY),.ENABLE_SWITCH_MODE(ENABLE_SWITCH_MODE),.DEMO_MENU(DEMO_MENU),.ENABLE_THUMB_TRANSPARENCY(ENABLE_THUMB_TRANSPARENCY),.ENABLE_AUDIO_IMAGE_BIND(ENABLE_AUDIO_IMAGE_BIND),.ENABLE_DIAGONAL_TRANSITION(ENABLE_DIAGONAL_TRANSITION),.ENABLE_AUDIO_PROGRESS(ENABLE_AUDIO_PROGRESS),.MENU_ITEM_BITS(MENU_ITEM_BITS),.ENABLE_SW4_THUMBNAILS(ENABLE_SW4_THUMBNAILS),.ENABLE_FULL_CONFIG_SAVE(ENABLE_FULL_CONFIG_SAVE),.ENABLE_CLOCK_TIMER(ENABLE_CLOCK_TIMER),.ENABLE_LOW_POWER_MENU(ENABLE_LOW_POWER_MENU)
    ) u_player_keys (
        .caption_enabled(caption_enabled),.clk(clk),.rst(rst),
        .key_plus_n(key_next),.key_minus_n(key_prev),.key_mode_n(key_auto),
        .display_sleep(display_sleep),.clock_command(clock_command),
        .key_confirm_n(key_confirm),.main_keys_sw(main_keys_sw),.thumbnail_switch(thumbnail_switch),
        .auto_play_enabled(auto_play_en),
        .next_event(key_next_press),.prev_event(key_prev_press),
        .auto_event(key_auto_press),.auto_value(key_auto_value),
        .restore_diagonal(restore_diagonal),.diagonal_selected(diagonal_selected),
        .volume(volume),.period_sec(period_seconds),.fade_level(fade_level),
        .period_change_valid(key_period_changed),.save_event(save_event),
        .audio_paused(audio_paused),.replay_event(replay_event),
        .playback_mode(playback_mode),.main_keys_music(main_keys_music),.main_keys_thumbnail(main_keys_thumbnail),
        .playback_ended(playback_end_sync[1]),.play_mode(),
        .source_wav(source_wav),.track_next_event(track_next_event),
        .track_prev_event(track_prev_event),
        .auto_mode(auto_mode),.volume_mode(volume_mode),
        .period_mode(period_mode),.fade_mode(fade_mode),
        .save_mode(save_mode),.source_mode(source_mode),.track_mode(track_mode),
        .menu_open(menu_open),.menu_level(menu_level),
        .menu_group(menu_group),.menu_item(menu_item),.menu_transparency(menu_transparency),.thumbnail_transparency(thumbnail_transparency),.audio_image_bind(audio_image_bind),.progress_visible(progress_visible),.visual_enabled(visual_enabled),
        .image_page(image_page),.brightness(brightness),.contrast(contrast),
        .thumb_mode(thumbnail_view),.thumb_enter(thumb_enter),.thumb_next(thumb_next),.thumb_prev(thumb_prev),
        .thumb_confirm(thumb_confirm),.thumb_back(thumb_back),
        .save_busy(save_busy),.restore_valid(restore_valid),.restore_ui(restore_ui),
        .restore_volume(restore_volume),
        .restore_period_valid(restore_period_valid),
        .restore_period_sec(restore_period_sec),
        .restore_fade_level(restore_fade_level),
        .restore_playback_mode(restore_playback_mode),.restore_main_keys_music(restore_main_keys_music),.restore_menu_transparency(restore_menu_transparency),.restore_thumbnail_transparency(restore_thumbnail_transparency),.restore_main_keys_thumbnail(restore_main_keys_thumbnail),.restore_audio_image_bind(restore_audio_image_bind),.restore_progress_visible(restore_progress_visible)
    );
    end else begin : g_legacy_keys
    assign clock_command=0;
    assign visual_enabled=1'b1;
    assign thumb_enter=0;assign thumb_next=0;assign thumb_prev=0;assign thumb_confirm=0;assign thumb_back=0;
    assign diagonal_selected=0;
    assign progress_visible=ENABLE_AUDIO_PROGRESS!=0;
    assign menu_transparency=2'd2;assign thumbnail_transparency=2'd2;assign audio_image_bind=0;
    assign image_page=1'b0;assign brightness=8'd255;assign contrast=8'd128;
    assign playback_mode=2'd0;
    assign main_keys_music=1'b0;
    assign main_keys_thumbnail=1'b0;
    assign audio_paused=1'b0;
    assign replay_event=1'b0;
    assign menu_open=1'b0;
    assign menu_level=1'b0;
    assign menu_group=2'd0;
    assign menu_item=2'd0;
    player_key_control #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ), .LONG_PRESS_MS(LONG_PRESS_MS)
    ) u_player_keys (
        .clk(clk), .rst(rst),
        .key_plus_n(key_next), .key_minus_n(key_prev), .key_mode_n(key_auto),
        .next_event(key_next_press), .prev_event(key_prev_press),
        .auto_event(key_auto_press), .auto_value(key_auto_value),
        .volume(volume), .volume_mode(volume_mode),
        .fade_mode(fade_mode), .fade_level(fade_level),
        .period_mode(period_mode), .period_sec(period_seconds),
        .period_change_valid(key_period_changed),
        .save_mode(save_mode), .auto_mode(auto_mode),
        .source_mode(source_mode),.track_mode(track_mode),
        .source_wav(source_wav),.track_next_event(track_next_event),
        .track_prev_event(track_prev_event),
        .save_event(save_event), .save_busy(save_busy),
        .restore_valid(restore_valid), .restore_volume(restore_volume),
        .restore_period_valid(restore_period_valid), .restore_period_sec(restore_period_sec),
        .restore_fade_level(restore_fade_level)
    );
    end endgenerate
    generate if(USE_SCREEN_MENU==0) begin : g_no_caption_menu
        assign caption_enabled=0;
    end endgenerate
    audio_track_catalog_byte_names #(.ENABLE_CAPTION(ENABLE_CAPTION)) u_audio_track_catalog (
        .clk(clk),.rst(rst),.scan_reset(scan_start_pulse),.scan_done(scan_done),
        .found_valid(audio_found_valid && !cue_file_match),.found_name(audio_found_name),
        .found_cluster(audio_found_cluster),.found_size(audio_found_size),
        .next_event(track_next_event || auto_track_next),.prev_event(track_prev_event),
        .track_count(track_count),.selected_index(selected_track),
        .selected_cluster(selected_audio_cluster),.selected_size(selected_audio_size),
        .track_change(track_change),.ready(audio_catalog_ready),
        .caption_lookup_index(binding_file_tag[2:0]),.selected_short_name(caption_lookup_name),.selected_short_name_valid(caption_lookup_valid)
    );
    always @(posedge clk or posedge rst) begin
        if(rst) begin caption_audio_name<=0;caption_audio_name_valid<=0;caption_audio_tag<=0;end
        else if(caption_audio_tag!=binding_file_tag) begin caption_audio_tag<=binding_file_tag;caption_audio_name_valid<=0;end
        else if(!caption_audio_name_valid && caption_lookup_valid) begin
            caption_audio_name<=caption_lookup_name;caption_audio_name_valid<=1;
        end
    end
    generate if(ENABLE_CAPTION!=0) begin : g_caption
        caption_engine #(.SD_TIMEOUT_CYCLES((CLK_FREQ_HZ/1000)*SD_READ_TIMEOUT_MS)) u_caption (
            .clk(clk),.rst(rst),.pixel_clk(pixel_clk),.pixel_rst(pixel_rst),.frame_start(frame_start),
            .enabled(caption_pixel_enabled),.menu_open(caption_pixel_menu_open),.source_wav(caption_pixel_source_wav),
            .stream_reset_pixel(binding_stream_reset_pixel),.sample_started(binding_sample_started),.audio_end(audio_end),
            .pixel_file_tag(progress_file_tag),.audio_file_tag(binding_file_tag),.pixel_file_size(progress_file_size),
            .audio_file_size(caption_audio_size),.played_samples(progress_played_samples),.audio_name(caption_audio_name),.audio_name_valid(caption_audio_name_valid),
            .scan_reset(scan_start_pulse),.scan_done(scan_done),.found_valid(caption_found_valid),.found_name(caption_found_name),
            .found_cluster(caption_found_cluster),.found_size(caption_found_size),.sd_initialized(sd_init_done),
            .sd_owned(caption_owned),.sd_valid(card_sd_sec_read_data_valid),.sd_byte(card_sd_sec_read_data),.sd_done(card_sd_sec_read_end),
            .sectors_per_cluster(audio_spc),.fat_lba(audio_fat_lba),.data_lba(audio_data_lba),.max_cluster(audio_max_cluster),
            .sd_request(caption_request),.sd_address(caption_address),.transport_recover(caption_transport_recover),
            .bitmap_address(caption_bitmap_address),.bitmap_read_bank(caption_bitmap_bank),.bitmap_byte(caption_bitmap_byte),
            .frame_visible(caption_frame_visible),.frame_bank(caption_frame_bank),.frame_width(caption_frame_width),.frame_text_x(caption_frame_text_x),.frame_color_id(caption_frame_color_id),
            .status(),.ownership_error());
    end else begin : g_no_caption
        assign caption_request=0;assign caption_address=0;assign caption_transport_recover=0;
        assign caption_frame_color_id=0;
        assign caption_bitmap_byte=0;assign caption_frame_visible=0;assign caption_frame_bank=0;assign caption_frame_width=0;assign caption_frame_text_x=0;
    end endgenerate
    generate if(ENABLE_TRANSITION_CUE!=0) begin : g_transition_cue
        // Successful manual commit event; one held toggle crosses to pixel_clk.
        // The first-stage path remains timed by the existing clock constraints.
        (* async_reg="true" *) reg [1:0] manual_sync;
        reg manual_seen;
        wire manual_pulse=manual_sync[1]!=manual_seen;
        always @(posedge pixel_clk or posedge pixel_rst) begin
            if(pixel_rst) begin manual_sync<=0;manual_seen<=0;end
            else begin manual_sync<={manual_sync[0],manual_cue_toggle};manual_seen<=manual_sync[1];end
        end
        // Frame-boundary commits permit at most one picture cue per frame.
        // Merge transition-start and post-ACK manual pulses for that commit.
        reg cue_commit_guard;
        wire cue_commit_event=(cue_trigger || manual_pulse) && (!cue_commit_guard || frame_start);
        always @(posedge pixel_clk or posedge pixel_rst) begin
            if(pixel_rst) cue_commit_guard<=0;
            else if(cue_commit_event) cue_commit_guard<=1;
            else if(frame_start) cue_commit_guard<=0;
        end
        transition_cue_synth u_cue_player (
            .clk(pixel_clk),.rst_n(!pixel_rst),.trigger(cue_commit_event),
            .sample_tick(audio_sample_tick),.sample_ready(cue_sample_ready),
            .sample_data(cue_sample),.sample_valid(cue_sample_valid));
        assign cue_request=1'b0;assign cue_address=32'd0;
    end else begin : g_no_transition_cue
        assign cue_request=0;assign cue_address=0;assign cue_sample=0;assign cue_sample_valid=0;
    end endgenerate
    // 查找已收录图片的首簇号；旧sector命名保留，文件大小由size_lut提供。
    function [31:0] sector_lut;  // 返回图片起始扇区
        input [1:0] idx;  // 图片编号
        begin
            case (idx)
                2'd0:
                    sector_lut = img_sector0;  // 返回图片 0 的起始扇区
                2'd1:
                    sector_lut = img_sector1;  // 返回图片 1 的起始扇区
                2'd2:
                    sector_lut = img_sector2;  // 返回图片 2 的起始扇区
                2'd3:
                    sector_lut = img_sector3;  // 返回图片 3 的起始扇区
                default:
                    sector_lut = img_sector0;  // 默认返回图片 0 的起始扇区
            endcase
        end
    endfunction
    function [31:0] size_lut;
        input [1:0] idx;
        begin
            case(idx)
                0:size_lut=img_size0;1:size_lut=img_size1;
                2:size_lut=img_size2;default:size_lut=img_size3;
            endcase
        end
    endfunction

    wire [IMAGE_BITS:0] uncached_image;
    wire navigation_requested = (binding_navigation || (ENABLE_THUMBNAILS!=0 && thumb_select_pending) || next_req_pending || prev_req_pending ||
                                 (auto_play_en && auto_tick && !key_auto_press && img_found_count > 1));
    wire load_requested = !first_image_committed || navigation_requested;
    wire [5:0] thumb_fill_candidate;
    wire [3:0] thumb_page_ready=thumbnail_ready >> {thumbnail_focus[4:2],2'b00};
    wire [3:0] thumb_page_failed=failed_images >> {thumbnail_focus[4:2],2'b00};
    generate if(ENABLE_THUMBNAILS!=0) begin : g_thumbnail_fill
        reg [5:0] candidate;
        reg [2:0] page_q;
        reg [3:0] ready_q,failed_q;
        reg [IMAGE_BITS:0] count_q;
        integer thumb_slot;
        reg [4:0] thumb_probe;
        assign thumb_fill_candidate=thumbnail_view && !thumbnail_waiting &&
            page_q==thumbnail_focus[4:2] && count_q==img_found_count ? candidate : 6'd0;
        always @(posedge clk or posedge rst) begin
            if(rst) begin candidate<=0;page_q<=0;ready_q<=0;failed_q<=0;count_q<=0;end
            else begin
                page_q<=thumbnail_focus[4:2];ready_q<=thumb_page_ready;failed_q<=thumb_page_failed;
                count_q<=img_found_count;candidate<=0;
                if(thumbnail_view && !thumbnail_waiting && page_q==thumbnail_focus[4:2] && count_q==img_found_count) begin
                    // Reverse loop with last assignment selecting the first missing entry.
                    for(thumb_slot=3;thumb_slot>=0;thumb_slot=thumb_slot-1) begin
                        thumb_probe={page_q,thumb_slot[1:0]};
                        if(thumb_probe<count_q && !failed_q[thumb_slot] && !ready_q[thumb_slot])
                            candidate<={1'b1,thumb_probe};
                    end
                end
            end
        end
    end else begin : g_no_thumbnail_fill
        assign thumb_fill_candidate=6'd0;
    end endgenerate
    wire [IMAGE_BITS-1:0] load_candidate_raw = load_requested ? requested_image :
        thumb_fill_candidate[5] ? thumb_fill_candidate[IMAGE_BITS-1:0] : uncached_image[IMAGE_BITS-1:0];
    reg [IMAGE_BITS-1:0] load_candidate_q,candidate_current_image_q;
    reg candidate_requested_q,candidate_cached_q,requested_cached_q,load_bank_found_q;
    reg [1:0] requested_bank_q,load_bank_q;
    reg [3:0] cache_epoch,candidate_epoch_q;
    wire [IMAGE_BITS-1:0] load_candidate=MAX_IMAGES>4 ? load_candidate_q : load_candidate_raw;
    // A resident target can be committed without waiting for background DMA.
    wire cached_navigation_ready=MAX_IMAGES>4 && first_image_committed &&
        navigation_requested && candidate_ready && candidate_cached_q && requested_cached_q &&
        (!load_busy || requested_bank_q!=write_buf_idx);
    wire candidate_ready=image_read_valid && candidate_current_image_q==img_idx &&
        candidate_requested_q==load_requested &&
        (!load_requested || load_candidate==requested_image) &&
        candidate_epoch_q==cache_epoch && image_read_index==load_candidate;
    // Only an unrelated speculative load yields. Keep resident commits fast,
    // and let an already requested/finishing image complete normally.
    assign preload_preempt_pending=ENABLE_ADAPTIVE_SCALING!=0 && MAX_IMAGES>4 &&
        load_busy && preload_background && first_image_committed && manual_nav_pending &&
        (next_req_pending || prev_req_pending || (ENABLE_THUMBNAILS!=0 && thumb_select_pending)) &&
        candidate_ready && !candidate_cached_q && requested_image!=load_idx &&
        !source_done_seen && !write_done_seen && !bmp_load_done && !write_finish_pulse &&
        !recovery_pending && !recovery_blocked;
    // Never truncate a physical SD sector. The arbiter above suppresses the
    // old background client's next grant until this same-clock abort is seen.
    wire preload_preempt_safe=preload_preempt_pending &&
        (!bmp_sector_owner || card_sd_sec_read_end) &&
        sd_init_done && startup_ready && sd_reset_count==0;
    // Decode the catalog/cache in separate clocks before issuing a load/commit.
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            load_candidate_q<=0;candidate_current_image_q<=0;candidate_requested_q<=0;
            candidate_cached_q<=0;requested_cached_q<=0;load_bank_found_q<=0;
            requested_bank_q<=0;load_bank_q<=0;candidate_epoch_q<=0;
        end else begin
            load_candidate_q<=load_candidate_raw;candidate_current_image_q<=img_idx;
            candidate_requested_q<=load_requested;candidate_cached_q<=image_complete[load_candidate];
            requested_cached_q<=requested_cached;requested_bank_q<=requested_bank;
            load_bank_found_q<=load_bank_found;load_bank_q<=load_bank;candidate_epoch_q<=cache_epoch;
        end
    end
    (* max_fanout=8 *) wire selection_ready;
    // The reader retains the sole volume catalog; only a queried tuple is held here.
    wire catalog_lookup_busy,catalog_lookup_valid,catalog_lookup_missing;
    wire [63:0] catalog_lookup_pair;
    reg image_read_valid;
    wire catalog_lookup_start=MAX_IMAGES>4 && scan_ready_for_load && !scan_start_pulse &&
        !load_abort && preload_release_count==0 && !bmp_sd_recover && !recovery_pending && !recovery_blocked &&
        !catalog_lookup_busy && !catalog_lookup_valid && !catalog_lookup_missing &&
        (!image_read_valid || image_read_index!=load_candidate);
    wire [63:0] image_read=catalog_lookup_pair;
    reg [IMAGE_BITS-1:0] image_read_index;
    reg [IMAGE_BITS-1:0] bank_image[0:3];
    reg [3:0] bank_valid;
    reg [1:0] victim_cursor;
    reg [1:0] previous_display_bank;
    reg previous_display_valid;

    wire [2:0] bound_commit_track=pending_image;
    assign thumb_selection_done=frame_commit_done && frame_commit_applied && pending_image==thumb_selected_image && thumb_select_pending;
    assign thumbnail_image_count=img_found_count;
    assign thumbnail_load_index=load_idx;
    assign thumbnail_load_active=load_busy;
    assign thumbnail_failed=failed_images;
    generate if(ENABLE_THUMBNAILS!=0) begin : g_thumbnails
        thumbnail_controller #(.RESIDENT_MODE(RESIDENT_THUMBNAILS),.RESPONSIVE_SELECTION(FULLSCREEN_THUMBNAILS),.CONFIRM_SELECTION(ENABLE_CONFIRM_KEY)) u_thumbnail_control (
            .clk(clk),.rst(rst),.enter(thumb_enter),.next_key(thumb_next),.prev_key(thumb_prev),
            .confirm_key(thumb_confirm),.back_key(thumb_back),.image_count(thumbnail_image_count),
            .current_image(img_idx),.thumbnail_ready(thumbnail_ready),.failed_images(thumbnail_failed),
            .selection_done(thumb_selection_done),.selection_failed(recovery_blocked),
            .view_mode(thumbnail_view),.waiting(thumbnail_waiting),.focus_index(thumbnail_focus),
            .target_index(thumb_target),.select_event(thumb_select_event)
        );
    end else begin : g_no_thumbnails
        assign thumbnail_view=0;assign thumbnail_waiting=0;assign thumbnail_focus=0;
        assign thumb_select_event=0;assign thumb_target=0;
    end endgenerate
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            thumb_select_pending<=0;thumb_selected_image<=0;thumbnail_flush_pending<=0;
            thumbnail_publish_toggle<=0;thumbnail_publish_index<=0;thumbnail_invalidate_toggle<=0;
        end else if(ENABLE_THUMBNAILS!=0) begin
            if(thumb_select_event) begin thumb_select_pending<=1;thumb_selected_image<=thumb_target;end
            else if(thumb_selection_done || recovery_blocked || failed_images[thumb_selected_image]) thumb_select_pending<=0;
            if(thumbnail_flush_pending && thumbnail_ready[thumbnail_publish_index]) thumbnail_flush_pending<=0;
            if(load_busy && source_done_seen && write_done_seen && write_started &&
               !bmp_load_error && !write_fifo_overflow && !load_timeout_expired && !recovery_pending) begin
                thumbnail_publish_index<=load_idx;thumbnail_publish_toggle<=!thumbnail_publish_toggle;
                thumbnail_flush_pending<=!thumbnail_ready[load_idx];
            end
            if(scan_start_pulse) begin
                thumbnail_invalidate_toggle<=!thumbnail_invalidate_toggle;
                thumbnail_flush_pending<=0;
            end
        end
    end


    reg [1:0] requested_bank,load_bank;
    reg requested_cached,load_bank_found;
    integer bank_slot,bank_probe;
    always @(posedge clk or posedge rst) begin
        if(rst) begin image_read_index<=0;image_read_valid<=0;end
        else if(scan_start_pulse) begin image_read_index<=0;image_read_valid<=0;end
        else if(load_abort && preload_release_count!=0) image_read_valid<=0;
        else if(catalog_lookup_start) begin
            image_read_index<=load_candidate;image_read_valid<=0;
        end else if(catalog_lookup_valid) begin
            image_read_valid<=1;
        end else if(catalog_lookup_missing) image_read_valid<=0;
    end
    wire catalog_lookup_fault=MAX_IMAGES>4 && catalog_lookup_missing &&
        !recovery_pending && !recovery_blocked && !scan_start_pulse;
    always @* begin
        requested_bank=requested_image[1:0];requested_cached=0;
        load_bank=load_candidate[1:0];load_bank_found=0;
        if(MAX_IMAGES>4) begin
            for(bank_slot=0;bank_slot<4;bank_slot=bank_slot+1)
                if(bank_valid[bank_slot] && bank_image[bank_slot]==load_candidate) begin
                    requested_bank=bank_slot[1:0];requested_cached=1;
                end
            for(bank_slot=0;bank_slot<4;bank_slot=bank_slot+1)
                if(!load_bank_found && !bank_valid[bank_slot] &&
                   !(display_valid && bank_slot[1:0]==disp_buf_idx) &&
                   !(previous_display_valid && bank_slot[1:0]==previous_display_bank)) begin
                    load_bank=bank_slot[1:0];load_bank_found=1;
                end
            for(bank_slot=0;bank_slot<4;bank_slot=bank_slot+1) begin
                bank_probe=(victim_cursor+bank_slot)&3;
                if(!load_bank_found && !(display_valid && bank_probe[1:0]==disp_buf_idx) &&
                   !(previous_display_valid && bank_probe[1:0]==previous_display_bank) &&
                   !(frame_commit_pending && bank_probe[1:0]==pending_buf_idx)) begin
                    load_bank=bank_probe[1:0];load_bank_found=1;
                end
            end
        end
    end
    wire player_next_event, player_prev_event;
    wire transition_busy;
    wire fade_ready = (TRANSITION_FRAMES != 0) && display_valid &&
                      scan_done && selection_ready &&
                      !load_busy && !recovery_pending && !recovery_blocked &&
                      !frame_commit_pending && !next_req_pending && !prev_req_pending;
    wire fade_next_request = key_next_press && fade_ready && usable_next[IMAGE_BITS] &&
                             usable_next[IMAGE_BITS-1:0] != img_idx &&
                             image_complete[usable_next[IMAGE_BITS-1:0]];
    wire fade_prev_request = key_prev_press && fade_ready && usable_prev[IMAGE_BITS] &&
                             usable_prev[IMAGE_BITS-1:0] != img_idx &&
                             image_complete[usable_prev[IMAGE_BITS-1:0]];

    generate
        if (TRANSITION_FRAMES == 0) begin : g_transition_bypass
            assign player_next_event = key_next_press;
            assign player_prev_event = key_prev_press;
            assign transition_busy = 1'b0;
            assign transition_alpha = 8'hff;
            assign transition_wipe_active = 1'b0;
            assign transition_ramp = 5'd0;
        end else begin : g_transition_enabled
            reg [1:0] active_index_q;
            reg active_valid_q;
            wire transition_next_event, transition_prev_event;
            wire index_commit = active_valid_q && active_valid &&
                                active_index != active_index_q;
            always @(posedge pixel_clk or posedge pixel_rst) begin
                if (pixel_rst) begin
                    active_index_q <= 0;
                    active_valid_q <= 0;
                end else begin
                    active_index_q <= active_index;
                    active_valid_q <= active_valid;
                end
            end

            video_fade_transition #(.FADE_FRAMES(TRANSITION_FRAMES)) u_transition (
                .ctrl_clk(clk), .ctrl_rst_n(~rst),
                .next_event_in(fade_next_request), .prev_event_in(fade_prev_request),
                .next_event_out(transition_next_event),
                .prev_event_out(transition_prev_event), .fade_busy(transition_busy),
                .pix_clk(pixel_clk), .pix_rst_n(~pixel_rst),
                .player_active(active_valid), .frame_start(frame_start),
                .index_commit(index_commit), .active_index(active_index),
                .alpha_out(transition_alpha), .fade_active(),
                .wipe_active(transition_wipe_active), .ramp_out(transition_ramp),
                .transition_kind()
            );
            assign player_next_event = transition_next_event ||
                                        (key_next_press && !fade_next_request && !transition_busy);
            assign player_prev_event = transition_prev_event ||
                                        (key_prev_press && !fade_prev_request && !transition_busy);
        end
    endgenerate

    // Preserve the validated request guard when selecting SD50 or SD80.
    media_player_control #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ), .ENABLE_REQUEST_GUARD(CLK_FREQ_HZ==80_000_000 || CLK_FREQ_HZ==50_000_000), .AUTO_PLAY_MS(AUTO_PLAY_MS),.MAX_IMAGES(MAX_IMAGES),.ENABLE_THUMBNAILS(ENABLE_THUMBNAILS),.ENABLE_AUDIO_IMAGE_BIND(ENABLE_AUDIO_IMAGE_BIND)
    ) u_media_player_control (
        .clk(clk), .rst(rst),
        .next_event(player_next_event), .prev_event(player_prev_event),.browse_hold(thumbnail_view && (RESIDENT_THUMBNAILS==0 || thumbnail_waiting || thumbnail_focus!=img_idx)),
        .auto_event(key_auto_press), .auto_value(key_auto_value),
        .restore_auto_valid(restore_auto_valid),
        .restore_auto_enabled(restore_auto_enabled),
        .period_change_valid(key_period_changed), .period_seconds(period_seconds),
        .period_cfg_valid(period_cfg_valid), .period_cfg_cycles(period_cfg_cycles),
        .scan_done(scan_done), .img_found_count(img_found_count), .img_idx(img_idx),
        .failed_images(failed_images), .image_complete(image_complete),
        .display_valid(display_valid),
        .load_busy(load_busy), .recovery_blocked(recovery_blocked),
        .clear_requests((clear_play_requests && !(ENABLE_AUDIO_IMAGE_BIND!=0 && commit_is_bound &&
            (key_next_press || key_prev_press))) || fade_next_request || fade_prev_request ||
            (binding_changed && !manual_nav_pending && !key_next_press && !key_prev_press)),
        .stop_playback(stop_playback),
        .reset_timer(reset_play_timer || transition_busy ||
                     fade_next_request || fade_prev_request),
        .retry_next_event(retry_next_event),
        .pix_clk(pixel_clk), .pix_rst(pixel_rst), .frame_start(frame_start),
        .commit_image(request_commit), .commit_image_index(request_commit_index),
        .audio_image_bind(audio_image_bind),.commit_is_bound(commit_is_bound),.commit_track(bound_commit_track),
        .bound_allowed_pixel(bound_allowed_pixel),.bound_track_pixel(bound_track_pixel),.commit_applied(frame_commit_applied),
        .frame_commit_request_toggle(frame_commit_request_toggle),
        .frame_commit_request_index(frame_commit_request_index),
        .frame_commit_acknowledge_toggle(frame_commit_acknowledge_toggle),
        .active_index(active_index), .active_valid(active_valid),
        .auto_play_en(auto_play_en),
        .auto_cnt(auto_cnt), .auto_play_cycles(auto_play_cycles),
        .next_req_pending(next_req_pending), .prev_req_pending(prev_req_pending),
        .usable_next(usable_next), .usable_prev(usable_prev),
        .usable_first(usable_first), .uncached_image(uncached_image),
        .selection_ready(selection_ready), .auto_tick(auto_tick_raw)
    );

    // Preserve the displayed bank across every recoverable storage error.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wrfin_tgl_sync <= 0;
            write_ack_sync <= 0;
            scan_start_pulse <= 0;
            load_start_pulse <= 0;
            load_abort <= 0;
            scan_kicked <= 0;
            first_image_committed <= 0;
            display_valid <= 0;
            state_code <= 0;
            error_code <= 0;
            img_found_count <= 0;
            img_idx <= 0;
            load_idx <= 0;
            load_sector <= 0;load_file_size<=0;
            img_size0<=0;img_size1<=0;img_size2<=0;img_size3<=0;
            request_commit <= 0;
            request_commit_index <= 0;commit_is_bound<=0;bank_valid<=0;victim_cursor<=0;pending_image<=0;cache_epoch<=0;
            previous_display_bank<=0;previous_display_valid<=0;
            bank_image[0]<=0;bank_image[1]<=0;bank_image[2]<=0;bank_image[3]<=0;
            write_buf_idx <= 0;
            disp_buf_idx <= 0;
            image_complete <= 4'd0;
            frame_commit_ack_seen <= 1'b0;
            img_sector0 <= 0; img_sector1 <= 0;
            img_sector2 <= 0; img_sector3 <= 0;
            clear_play_requests <= 0;
            stop_playback <= 0;
            reset_play_timer <= 0;
            retry_next_event <= 0;
            auto_nav_pending <= 0;
            manual_nav_pending <= 0;
            picture_nav_cue_pending<=0;manual_commit_cue<=0;manual_cue_toggle<=0;
            auto_frame_commit <= 0;
            load_busy <= 0;preload_background<=0;preload_release_count<=0;
            load_timeout_cnt <= 0; scaling_elapsed_seconds <= 0;
            load_timeout_expired <= 0;
            source_done_seen <= 0;
            write_done_seen <= 0;
            write_started <= 0;
            ack_seen_low <= 0;
            failed_images <= 0;
            retry_count <= 0;
            scan_retry_count <= 0;
            recovery_pending <= 0;
            recovery_blocked <= 0;
            recovery_scan <= 0;
            retry_pending <= 0;
            recovery_count <= 0;
            sd_reset_count <= 0;
            init_wait_count <= 0;
        end else begin
            request_commit <= 0;
            clear_play_requests <= 0;
            stop_playback <= 0;
            reset_play_timer <= 0;
            retry_next_event <= 0;
            if(preload_release_count!=0) preload_release_count<=preload_release_count-1'b1;
            // Retain picture-key intent across a bounded load retry, but cancel
            // it when a thumbnail selection supersedes it or playback stops.
            if(clear_play_requests || recovery_blocked || stop_playback || thumb_select_event)
                picture_nav_cue_pending<=0;
            else if(key_next_press || key_prev_press) picture_nav_cue_pending<=1;
            if (clear_play_requests || recovery_pending || recovery_blocked)
                manual_nav_pending <= 0;
            else if (key_next_press || key_prev_press || thumb_select_event)
                manual_nav_pending <= 1;
            if (key_next_press || key_prev_press || clear_play_requests ||
                manual_nav_pending || !auto_play_en)
                auto_nav_pending <= 0;
            else if (auto_tick && !key_auto_press && img_found_count > 1)
                auto_nav_pending <= 1;
            wrfin_tgl_sync <= {wrfin_tgl_sync[1:0], write_finish_toggle};
            write_ack_sync <= {write_ack_sync[1:0], write_req_ack};
            if(frame_commit_done) begin
                frame_commit_ack_seen<=frame_commit_acknowledge_toggle;
                manual_commit_cue<=0;
            end
            if (frame_commit_done && frame_commit_applied) begin
                if(ENABLE_TRANSITION_CUE!=0 && manual_commit_cue && display_valid && pending_image!=img_idx)
                    manual_cue_toggle<=!manual_cue_toggle;
                cache_epoch<=cache_epoch+1'b1;
                // Automatic fade-out may still read the previous bank after commit ACK.
                if(MAX_IMAGES>4 && display_valid && pending_buf_idx!=disp_buf_idx) begin
                    previous_display_bank<=disp_buf_idx;previous_display_valid<=1;
                end
                frame_commit_ack_seen <= frame_commit_acknowledge_toggle;
                disp_buf_idx <= pending_buf_idx;
                img_idx <= MAX_IMAGES>4 ? pending_image : pending_buf_idx;
                display_valid <= 1'b1;
                first_image_committed <= 1'b1;
                retry_count <= 0;
                error_code <= 0;
            end
            scan_start_pulse <= 0;
            load_start_pulse <= 0;
            load_abort <= 0;
            state_code <= display_valid ? {1'b0,img_idx}+1'b1 : 0;
            if (sd_reset_count != 0) sd_reset_count <= sd_reset_count - 1'b1;
            if (ENABLE_CAPTION!=0 && caption_transport_recover) sd_reset_count<=8;
            if ((bmp_sd_recover && (MAX_IMAGES<=4 || bmp_scan_error || bmp_error==2)) ||
                (audio_started && wav_sector_done && wav_sector_error!=0)) sd_reset_count <= 8;
            if (scan_found_valid && img_found_count < MAX_IMAGES) begin
                if(MAX_IMAGES<=4) case(img_found_count)
                    0: begin img_sector0 <= scan_found_sector;img_size0<=scan_found_size;end
                    1: begin img_sector1 <= scan_found_sector;img_size1<=scan_found_size;end
                    2: begin img_sector2 <= scan_found_sector;img_size2<=scan_found_size;end
                    3: begin img_sector3 <= scan_found_sector;img_size3<=scan_found_size;end
                    default: ;
                endcase
                img_found_count <= img_found_count + 1'b1;
            end
            if (bmp_scan_reject) error_code <= 3'd1;
            if (scan_done && !scan_found_valid && !scan_start_pulse && !recovery_pending && img_found_count == 0 && error_code == 0)
                error_code <= 3'd4;

            if (!scan_kicked && (!sd_init_done || !startup_ready) && !recovery_pending && !recovery_blocked) begin
                if (init_wait_count >= REINIT_CYCLES-1) begin
                    error_code <= 3'd2;
                    recovery_blocked <= 1;
                end else init_wait_count <= init_wait_count + 1'b1;
            end else init_wait_count <= 0;

            if (load_busy) begin
                if (!write_ack_sync[2]) ack_seen_low <= 1;
                if (!write_started && ack_seen_low && write_req && write_ack_sync[2]) begin
                    write_started <= 1;
                    write_done_seen <= 0;
                end else if (write_started && write_finish_pulse)
                    write_done_seen <= 1;
                if (bmp_load_done) source_done_seen <= 1;
                if(ENABLE_ADAPTIVE_SCALING!=0) begin
                    if(load_timeout_cnt>=CLK_FREQ_HZ-1) begin
                        load_timeout_cnt<=0;scaling_elapsed_seconds<=scaling_elapsed_seconds+1'b1;
                        if(scaling_elapsed_seconds+1'b1>=scaling_timeout_seconds) load_timeout_expired<=1;
                    end else load_timeout_cnt<=load_timeout_cnt+1'b1;
                end else begin
                    if (load_timeout_cnt < LOAD_CYCLES) load_timeout_cnt <= load_timeout_cnt + 1'b1;
                    if (load_timeout_cnt >= LOAD_CYCLES-2) load_timeout_expired <= 1'b1;
                end
            end else begin
                load_timeout_cnt <= 0; scaling_elapsed_seconds <= 0;
                load_timeout_expired <= 1'b0;
            end

            // Error has priority over completion, even if they coincide.
            if ((load_busy && (bmp_load_error || write_fifo_overflow ||
                               load_timeout_expired)) || bmp_scan_error || catalog_lookup_fault) begin
                error_code <= catalog_lookup_fault || write_fifo_overflow ? 3'd3 :
                              bmp_scan_error || bmp_load_error ? bmp_error : 3'd2;
                load_abort <= 1;
                load_busy <= 0;
                source_done_seen <= 0;
                write_done_seen <= 0;
                write_started <= 0;
                reset_play_timer <= 1;
                recovery_pending <= 1;
                recovery_count <= 0;
                recovery_scan <= bmp_scan_error || catalog_lookup_fault;
                if (!bmp_load_error && !bmp_scan_error && !catalog_lookup_fault) sd_reset_count <= 8;
                if (bmp_scan_error || catalog_lookup_fault) begin
                    retry_pending <= scan_retry_count < MAX_RETRIES;
                    if (scan_retry_count < MAX_RETRIES) scan_retry_count <= scan_retry_count + 1'b1;
                end else if (retry_count < MAX_RETRIES) begin
                    retry_count <= retry_count + 1'b1;
                    retry_pending <= 1;
                end else begin
                    retry_pending <= 0;
                    failed_images[load_idx] <= 1;cache_epoch<=cache_epoch+1'b1;
                    image_complete <= image_complete & ~({{(MAX_IMAGES-1){1'b0}},1'b1} << load_idx);
                end
            end else if(preload_preempt_safe) begin
                // Keep the explicit navigation/cue pending. The incomplete bank
                // stays invalid and its thumbnail is never published as ready.
                load_abort<=1;load_busy<=0;preload_background<=0;
                preload_release_count<=6'd32;
                source_done_seen<=0;write_done_seen<=0;write_started<=0;ack_seen_low<=0;
                load_timeout_cnt<=0;scaling_elapsed_seconds<=0;load_timeout_expired<=0;
                retry_count<=0;reset_play_timer<=1;cache_epoch<=cache_epoch+1'b1;
                bank_valid[write_buf_idx]<=0;
            end else if (recovery_pending) begin
                reset_play_timer <= 1;
                if (recovery_count >= REINIT_CYCLES-1) begin
                    error_code <= 3'd2;
                    recovery_pending <= 0;
                    recovery_blocked <= 1;
                    stop_playback <= 1;
                end else if (recovery_count >= 32 && sd_init_done && startup_ready && sd_reset_count == 0 && bmp_ready &&
                             (MAX_IMAGES<=4 || !bmp_sector_owner)) begin
                    recovery_pending <= 0;
                    if (retry_pending) begin
                        if (recovery_scan) begin
                            scan_start_pulse <= 1;
                            scan_kicked <= 1;
                            img_found_count <= 0;
                            // Keep the displayed bank intact while rebuilding the catalog.
                            first_image_committed <= display_valid;
                            image_complete <= display_valid ? ({{(MAX_IMAGES-1){1'b0}},1'b1} << img_idx) : 0;
                            bank_valid<=display_valid ? (4'b0001<<disp_buf_idx) : 0;cache_epoch<=cache_epoch+1'b1;
                            failed_images <= 0;
                        end else begin
                            // Same bank/sector; writer ACK confirms FIFO restart.
                            load_start_pulse <= 1;
                            load_busy <= 1;
                            source_done_seen <= 0;
                            write_done_seen <= 0;
                            write_started <= 0;
                            ack_seen_low <= 0;
                            load_timeout_cnt <= 0; scaling_elapsed_seconds <= 0;
                        end
                    end else if (recovery_scan) begin
                        recovery_blocked <= 1;
                        stop_playback <= 1;
                    end else if (auto_play_en && usable_next[IMAGE_BITS]) begin
                        retry_next_event <= 1;
                    end
                end else recovery_count <= recovery_count + 1'b1;
            end else if (recovery_blocked) begin
                // An explicit navigation press permits a fresh bounded attempt.
                if (key_next_press || key_prev_press) begin
                    recovery_blocked <= 0;
                    recovery_pending <= 1;
                    recovery_count <= 0;
                    sd_reset_count <= 8;
                    recovery_scan <= 1;
                    retry_pending <= 1;
                    scan_retry_count <= 0;
                    retry_count <= 0;
                    clear_play_requests <= 1;
                    error_code <= 0;
                end
            end else if (sd_init_done && startup_ready && sd_reset_count == 0) begin
                if (load_busy && source_done_seen && write_done_seen && write_started) begin
                    load_busy <= 0;preload_background<=0;
                    source_done_seen <= 0;
                    write_done_seen <= 0;
                    write_started <= 0;
                    image_complete <= image_complete | ({{(MAX_IMAGES-1){1'b0}},1'b1} << load_idx);cache_epoch<=cache_epoch+1'b1;
                    if(MAX_IMAGES>4) begin bank_valid[write_buf_idx]<=1;bank_image[write_buf_idx]<=load_idx;end
                    if (!first_image_committed && !frame_commit_pending) begin
                        request_commit_index <= MAX_IMAGES>4 ? write_buf_idx : load_idx;
                        pending_image<=load_idx;commit_is_bound<=0;manual_commit_cue<=0;
                        request_commit <= 1;
                        auto_frame_commit <= 0;
                    end
                    retry_count <= 0;
                    error_code <= 0;
                end

                if (!scan_kicked && bmp_ready) begin
                    scan_start_pulse <= 1;
                    scan_kicked <= 1;
                    img_found_count <= 0;
                    failed_images <= 0;
                end else if (scan_ready_for_load && selection_ready &&
                             !scan_start_pulse && preload_release_count==0 && !thumbnail_flush_pending && ((bmp_ready && !load_busy) || cached_navigation_ready) &&
                             !load_start_pulse && !frame_commit_pending &&
                              !frame_commit_done && !request_commit) begin
                    // All bad: stop rather than repeatedly loading the same file.
                    if (!usable_first[IMAGE_BITS]) begin
                        stop_playback <= 1;
                        clear_play_requests <= 1;
                        recovery_blocked <= 1;
                        if (error_code == 0) error_code <= 3'd4;
                    end else if (load_requested && (MAX_IMAGES<=4 ? image_complete[requested_image] :
                                 candidate_ready && candidate_cached_q && requested_cached_q)) begin
                        request_commit_index <= MAX_IMAGES>4 ? requested_bank_q : requested_image;
                        pending_image<=requested_image;commit_is_bound<=requested_is_bound;
                        manual_commit_cue<=ENABLE_TRANSITION_CUE!=0 && display_valid && requested_image!=img_idx &&
                            (picture_nav_cue_pending || key_next_press || key_prev_press) &&
                            !thumb_select_pending && !thumb_select_event && !requested_is_bound;
                        request_commit <= 1;
                        // Keep the public signal name: it now also permits picture-key transitions.
                        // Thumbnail confirmation remains a silent hard cut.
                        auto_frame_commit <= (!manual_nav_pending &&
                            !key_next_press && !key_prev_press &&
                            (requested_is_bound || auto_nav_pending || (auto_play_en && auto_tick))) ||
                            (ENABLE_DIAGONAL_TRANSITION!=0 && display_valid && requested_image!=img_idx &&
                             (picture_nav_cue_pending || key_next_press || key_prev_press) &&
                             !thumb_select_pending && !thumb_select_event && !requested_is_bound);
                        clear_play_requests <= 1;
                        reset_play_timer <= 1;
                    end else if ((MAX_IMAGES>4 || !audio_started) && (load_requested || uncached_image[IMAGE_BITS] || thumb_fill_candidate[5]) &&
                                 (MAX_IMAGES<=4 || (candidate_ready && load_bank_found_q &&
                                  (!candidate_cached_q || thumb_fill_candidate[5] && !load_requested)))) begin
                        // Navigation has priority; otherwise preload the next uncached image.
                        preload_background<=first_image_committed && !load_requested;
                        load_idx <= load_candidate;
                        load_sector <= MAX_IMAGES>4 ? image_read[63:32] : sector_lut(load_candidate[1:0]);
                        load_file_size <= MAX_IMAGES>4 ? image_read[31:0] : size_lut(load_candidate[1:0]);
                        write_buf_idx <= MAX_IMAGES>4 ? load_bank_q : load_candidate;
                        if(MAX_IMAGES>4) begin
                            cache_epoch<=cache_epoch+1'b1;
                            if(bank_valid[load_bank_q]) image_complete <= image_complete & ~({{(MAX_IMAGES-1){1'b0}},1'b1} << bank_image[load_bank_q]);
                            bank_valid[load_bank_q]<=0;victim_cursor<=load_bank_q+1'b1;
                        end
                        load_start_pulse <= 1;
                        load_busy <= 1;
                        source_done_seen <= 0;
                        write_done_seen <= 0;
                        write_started <= 0;
                        ack_seen_low <= 0;
                        retry_count <= 0;
                        load_timeout_cnt <= 0; scaling_elapsed_seconds <= 0;
                        reset_play_timer <= 1;
                    end
                end
            end
        end
    end

    // FAT32目录扫描与簇链加载；保留img_sector/load_sector内部名称，现保存首簇号。
    fat32_bmp_reader #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .SD_READ_TIMEOUT_MS(SD_READ_TIMEOUT_MS),.MAX_IMAGES(MAX_IMAGES),.ENABLE_CAPTION(ENABLE_CAPTION),.ENABLE_ADAPTIVE_SCALING(ENABLE_ADAPTIVE_SCALING),.ENABLE_SHARED_SCALING_RAM(ENABLE_SHARED_SCALING_RAM)) fat32_bmp_reader_m0(
        .bmp_buffer_address(bmp_buffer_address),.bmp_buffer_write(bmp_buffer_write),
        .bmp_buffer_write_data(bmp_buffer_write_data),.bmp_buffer_read_data(bmp_buffer_read_data),
                 .scale_clk              (pixel_clk),
                 .scale_rst              (pixel_rst),
                 .load_abort             (load_abort),
                 .bmp_error              (bmp_error),
                 .load_error             (bmp_load_error),
                 .load_done              (bmp_load_done),
                 .scan_error             (bmp_scan_error),
                 .scan_reject            (bmp_scan_reject),
                 .sd_recover             (bmp_sd_recover),
                 .clk                    (clk),  // 时钟
                 .rst                    (rst),  // 高电平异步复位
                 .ready                  (bmp_ready),  // BMP 模块空闲标志

                 .scan_start             (scan_start_pulse),  // 扫描启动脉冲
                 .catalog_lookup_start(catalog_lookup_start),.catalog_lookup_index(load_candidate),
                 .catalog_lookup_busy(catalog_lookup_busy),.catalog_lookup_valid(catalog_lookup_valid),
                 .catalog_lookup_missing(catalog_lookup_missing),.catalog_lookup_pair(catalog_lookup_pair),
                 .scan_done              (scan_done),  // 扫描完成标志
                 .scan_found_valid       (scan_found_valid),  // 找到匹配图片的脉冲
                 .scan_found_cluster     (scan_found_sector),  // 首簇号（保留旧信号名）
                 .scan_found_total       (scan_found_total),  // 找到的图片总数
                 .caption_found_valid(caption_found_valid),.caption_found_name(caption_found_name),
                 .caption_found_cluster(caption_found_cluster),.caption_found_size(caption_found_size),
                 .audio_found_valid      (audio_found_valid),
                 .audio_found_name       (audio_found_name),
                 .audio_found_cluster    (audio_found_cluster),
                 .audio_found_size       (audio_found_size),
                 .audio_sectors_per_cluster(audio_spc),
                 .audio_fat_start_lba    (audio_fat_lba),
                 .audio_data_start_lba   (audio_data_lba),
                 .audio_max_cluster      (audio_max_cluster),

                 .load_start             (load_start_pulse),
                 .load_file_size         (load_file_size),
                 .scan_found_size        (scan_found_size),  // 目录文件长度
                 .load_cluster           (load_sector),  // 加载图片首簇号（保留旧信号名）

                 .sd_init_done           (sd_init_done),  // SD 卡初始化完成标志
                 .bmp_pixel_ready        (write_ready && load_busy && write_started && !bmp_load_error && !load_abort),
                 .bmp_width              (bmp_width),  // 目标图片宽度
                 .bmp_height             (bmp_height),  // 目标图片高度
                 .write_req              (write_req),  // 整帧写请求
                 .write_req_ack          (write_ack_sync[2]),  // 写请求应答
                 .sd_sec_read            (bmp_sd_sec_read),
                 .sd_sec_read_addr       (bmp_sd_sec_read_addr),
                 .sd_sec_read_data       (card_sd_sec_read_data),
                 .sd_sec_read_data_valid (card_sd_sec_read_data_valid && bmp_sector_owner),
                 .sd_sec_read_end        (card_sd_sec_read_end && bmp_sector_owner),
                 .bmp_data_wr_en         (bmp_data_wr_en),  // 像素写使能
                 .bmp_data               (bmp_data)  // RGB 像素数据
             );

    wire wav_sd_req, wav_sector_req;
    wire [31:0] wav_player_lba;
    wire wav_stream_active, wav_stream_end;

    generate if (AUDIO_AUTO_FILES != 0) begin : g_audio_auto
    localparam [2:0] WAIT_START=0,RUN_FILE=1,WAIT_QUIET=2,RESET_FILE=3,
                     START_FILE=4,LATCH_FILE=5;
    reg [2:0] audio_state;
    reg [4:0] reset_count;
    reg stream_reset,stream_start,switching;
    reg [31:0] file_cluster_q,file_size_q;
    reg [3:0] file_tag_q;
    reg [1:0] switch_ready_sync,stream_reset_pixel;
    wire progress_metadata_ready;
    if(ENABLE_AUDIO_PROGRESS!=0 || ENABLE_CAPTION!=0) begin : g_progress_metadata
        wire [35:0] file_tuple_pixel;
        player_settings_cdc #(.WIDTH(36),.RESET_VALUE(36'd0)) file_metadata (
            .src_clk(clk),.src_rst(rst),.src_value({file_tag_q,file_size_q}),
            .dst_clk(pixel_clk),.dst_rst(pixel_rst),.dst_value(file_tuple_pixel),.src_ready(progress_metadata_ready));
        assign progress_file_tag=file_tuple_pixel[35:32];
        assign progress_file_size=file_tuple_pixel[31:0];
        assign progress_available=progress_played_samples!=0 && !stream_reset_pixel[1] && progress_file_size>=2;
    end else begin : g_no_progress_metadata
        assign progress_metadata_ready=1;assign progress_file_tag=0;assign progress_file_size=0;
        assign progress_available=0;
    end
    assign caption_audio_size=file_size_q;
    assign binding_file_tag=file_tag_q;
    assign binding_stream_reset_pixel=stream_reset_pixel[1];

    wire file_valid,file_done,file_busy,sector_allow;
    wire [7:0] file_byte,file_error;
    wire [31:0] file_byte_offset;
    wire file_sector_req;
    wire [31:0] file_sector_lba;
    wire stream_error;

    assign audio_switching=switching;
    always @(posedge pixel_clk or posedge pixel_rst) begin
        if(pixel_rst) stream_reset_pixel<=2'b11;
        else stream_reset_pixel<={stream_reset_pixel[0],stream_reset};
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            audio_state<=WAIT_START;reset_count<=0;
            stream_reset<=0;stream_start<=0;switching<=0;
            file_cluster_q<=0;file_size_q<=0;file_tag_q<=0;
            switch_ready_sync<=2'b11;
        end else begin
            switch_ready_sync<={switch_ready_sync[0],audio_switch_ready};
            stream_start<=0;
            case(audio_state)
                WAIT_START: if(audio_started) begin
                    audio_state<=LATCH_FILE;
                end
                RUN_FILE: if(track_change || replay_event || auto_replay) begin
                    switching<=1;
                    audio_state<=WAIT_QUIET;
                end
                WAIT_QUIET: if(switch_ready_sync[1] && !wav_sector_busy &&
                               !wav_sector_req && !card_sd_sec_read_end) begin
                    stream_reset<=1;
                    reset_count<=0;
                    audio_state<=RESET_FILE;
                end
                RESET_FILE: if(reset_count==5'd20) begin
                    stream_reset<=0;
                    audio_state<=LATCH_FILE;
                end else reset_count<=reset_count+1'b1;
                LATCH_FILE: begin
                    // Hold a coherent file tuple until this stream is reset.
                    if(ENABLE_AUDIO_IMAGE_BIND!=0 || ENABLE_AUDIO_PROGRESS!=0 || ENABLE_CAPTION!=0) file_tag_q<={!file_tag_q[3],selected_track};
                    file_cluster_q<=selected_audio_cluster;
                    file_size_q<=selected_audio_size;
                    audio_state<=START_FILE;
                end
                START_FILE: if((ENABLE_AUDIO_IMAGE_BIND==0 || binding_metadata_ready) && progress_metadata_ready) begin
                    stream_start<=1;
                    switching<=0;
                    audio_state<=RUN_FILE;
                end
                default: audio_state<=WAIT_START;
            endcase
        end
    end

    fat32_file_streamer u_audio_file_streamer (
        .clk(clk),.rst_n(~rst && !stream_reset),.file_start(stream_start),
        .data_sector_allow(sector_allow && audio_state==RUN_FILE),
        .first_cluster(file_cluster_q),.file_size(file_size_q),
        .sectors_per_cluster(audio_spc),.fat_start_lba(audio_fat_lba),
        .data_start_lba(audio_data_lba),.max_cluster(audio_max_cluster),
        .file_busy(file_busy),.file_done(file_done),.file_valid(file_valid),
        .file_byte(file_byte),.file_byte_offset(file_byte_offset),
        .fs_error(file_error),.sector_req(file_sector_req),
        .sector_lba(file_sector_lba),.sector_busy(wav_sector_busy),
        .sector_valid(wav_sector_valid),.sector_byte(wav_sector_byte),
        .sector_byte_index(wav_sector_byte_index),.sector_done(wav_sector_done),
        .sector_error(wav_sector_error)
    );
    pcm_file_fifo #(.ADDR_WIDTH(MAX_IMAGES>4 ? 10 : 9),.ENABLE_STARTED_EVENT(ENABLE_AUDIO_IMAGE_BIND || ENABLE_CAPTION),.ENABLE_AUDIO_PROGRESS(ENABLE_AUDIO_PROGRESS || ENABLE_CAPTION)) u_audio_file_fifo (
        .wr_clk(clk),.wr_rst_n(~rst && !stream_reset),
        .file_valid(file_valid),.file_byte(file_byte),
        .file_done(file_done),.file_error(file_error),.sector_allow(sector_allow),
        .rd_clk(pixel_clk),.rd_rst_n(~pixel_rst && !stream_reset_pixel[1]),
        .sample_tick(audio_sample_tick),.sample_ready(audio_sample_ready),
        .sample_out(audio_sample_left),.sample_valid(audio_sample_valid),
        .stream_active(wav_stream_active),.stream_end(wav_stream_end),
        .stream_error(stream_error),.sample_started(binding_sample_started),.played_samples(progress_played_samples)
    );
    assign audio_sample_right=audio_sample_left;
    assign wav_sd_sec_read=wav_sector_req;
    sd_sector_adapter #(.TIMEOUT_CYCLES((CLK_FREQ_HZ/1000)*SD_READ_TIMEOUT_MS))
    u_audio_sector_adapter (
        .clk(clk),.rst_n(~rst && !stream_reset),.abort(1'b0),
        .sd_init_done(sd_init_done),.sector_req(file_sector_req),
        .sector_lba(file_sector_lba),.sector_busy(wav_sector_busy),
        .sector_done(wav_sector_done),.sector_valid(wav_sector_valid),
        .sector_byte(wav_sector_byte),.sector_byte_index(wav_sector_byte_index),
        .sector_error(wav_sector_error),.sd_sec_read(wav_sector_req),
        .sd_sec_read_addr(wav_sd_sec_read_addr),
        .sd_sec_read_data_valid(card_sd_sec_read_data_valid && audio_sector_owner),
        .sd_sec_read_end(card_sd_sec_read_end && audio_sector_owner),
        .sd_sec_read_data(card_sd_sec_read_data)
    );
    end else if (AUDIO_TOTAL_SECTORS != 0) begin : g_audio_enabled
    assign caption_audio_size=0;
    assign binding_file_tag=0;assign binding_stream_reset_pixel=0;assign binding_sample_started=0;
    assign progress_file_tag=0;assign progress_file_size=0;assign progress_played_samples=0;assign progress_available=0;
    assign audio_switching=1'b0;
    wav_stream_player u_wav_stream_player (
        .wr_clk(clk), .wr_rst_n(~rst),
        .play_enable(audio_play_enable),
        .start_lba(AUDIO_START_LBA), .total_sectors(AUDIO_TOTAL_SECTORS),
        .sd_req(wav_sd_req), .sd_lba(wav_player_lba),
        .sd_busy(wav_sector_busy), .sd_valid(wav_sector_valid),
        .sd_byte(wav_sector_byte), .sd_byte_index(wav_sector_byte_index),
        .sd_done(wav_sector_done), .sd_error(wav_sector_error),
        .rd_clk(pixel_clk), .rd_rst_n(~pixel_rst),
        .sample_tick(audio_sample_tick),
        .sample_out(audio_sample_left), .sample_valid(audio_sample_valid),
        .sample_ready(audio_sample_ready), .sample_counter(),
        .stream_active(wav_stream_active), .stream_end(wav_stream_end),
        .buffer_low()
    );
    assign audio_sample_right = audio_sample_left;
    assign wav_sd_sec_read = wav_sector_req;

    sd_sector_adapter #(.TIMEOUT_CYCLES((CLK_FREQ_HZ / 1000) * SD_READ_TIMEOUT_MS))
    u_wav_sector_adapter (
        .clk(clk), .rst_n(~rst), .abort(1'b0), .sd_init_done(sd_init_done),
        .sector_req(wav_sd_req), .sector_lba(wav_player_lba),
        .sector_busy(wav_sector_busy), .sector_done(wav_sector_done),
        .sector_valid(wav_sector_valid), .sector_byte(wav_sector_byte),
        .sector_byte_index(wav_sector_byte_index), .sector_error(wav_sector_error),
        .sd_sec_read(wav_sector_req), .sd_sec_read_addr(wav_sd_sec_read_addr),
        .sd_sec_read_data_valid(card_sd_sec_read_data_valid && audio_sector_owner),
        .sd_sec_read_end(card_sd_sec_read_end && audio_sector_owner),
        .sd_sec_read_data(card_sd_sec_read_data)
    );

    end else begin : g_audio_disabled
    assign caption_audio_size=0;
    assign binding_file_tag=0;assign binding_stream_reset_pixel=0;assign binding_sample_started=0;
    assign progress_file_tag=0;assign progress_file_size=0;assign progress_played_samples=0;assign progress_available=0;
        assign audio_switching=1'b0;
        assign audio_sample_valid=1'b0;
        assign audio_sample_left=16'sd0;
        assign audio_sample_right=16'sd0;
        assign wav_stream_active=1'b0;
        assign wav_stream_end=1'b0;
        assign wav_sd_sec_read=1'b0;
        assign wav_sd_sec_read_addr=32'd0;
        assign wav_sector_done=1'b0;
        assign wav_sector_error=8'd0;
    end endgenerate

    // SD 卡初始化与 SPI 扇区读取
    sd_card_top sd_card_top_m0(
                    .clk                    (clk),  // 时钟
                    .rst                    (transport_reset),  // 高电平异步复位
                    .SD_nCS                 (SD_nCS),  // SPI 片选（低有效）
                    .SD_DCLK                (SD_DCLK),  // SPI 时钟
                    .SD_MOSI                (SD_MOSI),  // SPI 主发从收
                    .SD_MISO                (SD_MISO),  // SPI 主收从发
                    .sd_init_done           (sd_init_done),  // SD 卡初始化完成标志
                    .sd_sec_read            (sd_sec_read),  // 扇区读请求
                    .sd_sec_read_addr       (sd_sec_read_addr),  // 读取扇区号（不是字节地址）
                    .sd_sec_read_data       (card_sd_sec_read_data),
                    .sd_sec_read_data_valid (card_sd_sec_read_data_valid),
                    .sd_sec_read_end        (card_sd_sec_read_end),
                    .sd_sec_write           (1'b0),  // 写卡使能（固定为 0，禁用写卡）
                    .sd_sec_write_addr      (32'd0),  // 写卡地址（固定为 0）
                    .sd_sec_write_data      (),  // 写卡数据输入（未连接）
                    .sd_sec_write_data_req  (),  // 写数据请求（未使用）
                    .sd_sec_write_end       ()  // 写卡完成信号（未使用）
                );

endmodule

// 按键同步与消抖（短按、长按输出单周期脉冲，稳定电平持续输出）
module key_press_debounce #(
        parameter integer CLK_FREQ_HZ = 100_000_000,  // 时钟频率（Hz）
        parameter integer DEBOUNCE_MS = 20,  // 消抖时间（ms）
        parameter integer LONG_PRESS_MS      = 1000  // 按键 长按时间（ms）
    )(
        input  wire clk,  // 时钟
        input  wire rst,  // 高电平异步复位
        input  wire button_in,  // 按键输入（低有效）
        output reg button_stable_out,  // 消抖后的按键电平（保持至下次确认变化）
        output reg long_press,  // 长按标志（长按后才有效）
        output reg short_press  // 短按标志（松开后才有效）
    );

    localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;  // 消抖周期数（由时钟频率和消抖时间换算）

    localparam integer DEBOUNCE_CNT_WIDTH = DEBOUNCE_CYCLES > 1 ? $clog2(DEBOUNCE_CYCLES) : 1;
    localparam integer LONG_CYCLES = (CLK_FREQ_HZ / 1000) * LONG_PRESS_MS;
    localparam integer LONG_CNT_WIDTH = LONG_CYCLES > 1 ? $clog2(LONG_CYCLES) : 1;

    // Only the verified production timing uses encoded counters. All other
    // parameter combinations retain the original binary implementation.
    localparam integer USE_SHIFT_COUNTERS=CLK_FREQ_HZ==50_000_000 &&
        DEBOUNCE_MS==20 && LONG_PRESS_MS==500;
    localparam [DEBOUNCE_CNT_WIDTH-1:0] CNT_START=USE_SHIFT_COUNTERS ? 1 : 0;
    localparam [LONG_CNT_WIDTH-1:0] LONG_START=USE_SHIFT_COUNTERS ? 1 : 0;
    wire [DEBOUNCE_CNT_WIDTH-1:0] cnt_next;
    wire [LONG_CNT_WIDTH-1:0] long_press_cnt_next;
    reg short_press_eligible;
    wire debounce_done=USE_SHIFT_COUNTERS ? cnt==20'hf1e45 : cnt>=DEBOUNCE_CYCLES-1;
    wire long_counting=USE_SHIFT_COUNTERS ? long_press_cnt!=25'h0d40870 : long_press_cnt<LONG_CYCLES-1;
    wire short_limit_met=USE_SHIFT_COUNTERS ? short_press_eligible : long_press_cnt>(CLK_FREQ_HZ/100-1);
    generate if(USE_SHIFT_COUNTERS!=0) begin : g_shift_key_counters
        // State at old binary count999999/24999999 is the terminal state.
        // At old count499999 the following edge reaches the short minimum.
        assign cnt_next={cnt[0]^cnt[3],cnt[DEBOUNCE_CNT_WIDTH-1:1]};
        assign long_press_cnt_next={long_press_cnt[0]^long_press_cnt[3],long_press_cnt[LONG_CNT_WIDTH-1:1]};
    end else begin : g_binary_key_counters
        assign cnt_next=cnt+1'b1;
        assign long_press_cnt_next=long_press_cnt+1'b1;
    end endgenerate

    reg button_sync0;  // 按键一级同步
    reg button_sync1;  // 按键二级同步
    reg button_stable;  // 已确认的按键稳定电平
    reg [DEBOUNCE_CNT_WIDTH-1:0] cnt;  // 消抖计数
    reg [LONG_CNT_WIDTH-1:0] long_press_cnt;  // 长按计数
    reg long_press_marked;  // 长按标记（长按后才有效）

    // 复位为松开状态，电平变化后连续计时消抖
    always @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            button_sync0  <= 1'b1;
            button_sync1  <= 1'b1;
            button_stable <= 1'b1;
            cnt           <= CNT_START;
            button_stable_out <= 1'b1;
            long_press <= 1'b0;
            short_press <= 1'b0;
            long_press_marked <= 1'b0;
            short_press_eligible <= 1'b0;
            long_press_cnt <= LONG_START;
        end
        else
        begin
            button_sync0 <= button_in;  // 第一级采样
            button_sync1 <= button_sync0;  // 第二级同步

            if (button_sync1 == button_stable)  // 同步电平与已确认电平相同，清零计数
            begin
                cnt <= CNT_START;
            end
            else
            begin
                // 新电平持续达到消抖时间后，接受此次变化
                if (debounce_done)
                begin
                    button_stable <= button_sync1;  // 保存新稳定电平
                    button_stable_out <= button_sync1;  // 更新消抖输出电平
                    cnt           <= CNT_START;
                end
                else
                begin
                    cnt <= cnt_next;  // 新电平持续中，继续消抖计时
                end
            end

             long_press <= 1'b0;
             short_press <= 1'b0;
            // 按键消抖后仍按住，累计长按时间
            if (button_stable_out == 1'b0)
            begin
                if(USE_SHIFT_COUNTERS!=0 && long_press_cnt==25'h10a9c64)
                    short_press_eligible <= 1'b1;
                if (long_counting)
                begin
                    long_press_cnt <= long_press_cnt_next;  // 累计稳定按下时间
                end
                else if (!long_press_marked)  // 同一次长按只触发一次
                begin
                    // 记录长按标记，并输出长按信号
                    long_press_marked <= 1'b1;
                    long_press <= 1'b1;
                end
            end
            else
            begin
                short_press_eligible <= 1'b0;
                // 松开时判断短按（消抖后的按住计数约超过 10 ms，且未到长按阈值）
                if (short_limit_met && long_counting)
                begin
                    short_press <= 1'b1;
                    long_press_cnt   <= LONG_START;
                    long_press_marked <= 1'b0;
                end
                else
                begin
                    long_press_cnt   <= LONG_START;
                    long_press_marked <= 1'b0;
                end
            end
        end
    end
endmodule

