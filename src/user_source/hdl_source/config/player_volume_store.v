`timescale 1ns/1ps
// UI adapter: explicit snapshot -> update -> save -> verified result.
module player_volume_store #(
    parameter integer CLK_HZ = 100000000,
    parameter integer ENABLE_PLAY_OPTIONS = 0,
    parameter integer ENABLE_FULL_CONFIG_SAVE = 0,
    parameter integer ENABLE_MENU_TRANSPARENCY = 0,
    parameter integer ENABLE_THUMB_TRANSPARENCY = 0,
    parameter integer ENABLE_DIAGONAL_TRANSITION=0,
    parameter integer ENABLE_AUDIO_PROGRESS = 0,
    parameter integer ENABLE_AUDIO_IMAGE_BIND = 0
) (
    input wire clk, rst,
    input wire save_mode, save_event,
    input wire [7:0] volume,
    input wire [7:0] brightness,contrast,
    input wire visual_enabled,caption_enabled,source_wav,
    input wire [5:0] period_sec,
    input wire auto_enabled,
    input wire [1:0] fade_level,
    input wire [1:0] playback_mode,
    input wire main_keys_music,
    input wire [1:0] menu_transparency,
    input wire [1:0] thumbnail_transparency,
    input wire main_keys_thumbnail,
    input wire audio_image_bind,
    input wire diagonal_selected,
    output wire restore_diagonal,
    input wire progress_visible,
    output wire restore_valid,
    output wire [7:0] restore_volume,
    output wire [23:0] restore_ui,
    output reg restore_period_valid,
    output reg [5:0] restore_period_sec,
    output wire restore_auto_valid,
    output wire restore_auto_enabled,
    output wire [1:0] restore_fade_level,
    output wire [1:0] restore_playback_mode,
    output wire restore_main_keys_music,
    output wire [1:0] restore_menu_transparency,
    output wire [1:0] restore_thumbnail_transparency,
    output wire restore_main_keys_thumbnail,
    output wire restore_audio_image_bind,
    output wire restore_progress_visible,
    output wire save_busy,
    output reg [1:0] save_status, // 0 SAVE, 1 BUSY, 2 OK, 3 FAIL
    input wire flash_miso,
    output wire flash_cs_n, flash_sclk, flash_mosi, flash_wp_n, flash_hold_n
);
    reg [1:0] state;
    reg mode_q;
    reg [7:0] snapshot;
    reg [5:0] snapshot_period_sec;
    reg [7:0] snapshot_extra;
    reg [7:0] snapshot_mode;
    reg [23:0] snapshot_ui;
    wire [23:0] live_ui;
    assign restore_ui=live_ui;
    wire [7:0] live_mode;
    wire extended_mode=ENABLE_THUMB_TRANSPARENCY!=0 && ((ENABLE_DIAGONAL_TRANSITION!=0 && live_mode[7] && !live_mode[5] && (ENABLE_AUDIO_IMAGE_BIND!=0 || !live_mode[4]) && (ENABLE_AUDIO_PROGRESS!=0 || !live_mode[6])) || live_mode[7:4]==4'ha || ENABLE_AUDIO_IMAGE_BIND!=0 && live_mode[7:4]==4'hb || ENABLE_AUDIO_PROGRESS!=0 && (live_mode[7:4]==4'he || ENABLE_AUDIO_IMAGE_BIND!=0 && live_mode[7:4]==4'hf)) && live_mode[1:0]<=2;
    // The service applies only validated 1000..60000 ms records or its
    // 3000 ms default. The UI's repeated division therefore fits 16 bits.
    reg [15:0] restore_remainder;
    reg [5:0] restore_count;
    reg restore_pending;
    reg [31:0] expected_version;
    wire ready, fatal_error, save_done, load_done, stored_valid;
    wire [31:0] active_version;
    wire [7:0] live_volume;
    wire [31:0] live_period_ms;
    wire [7:0] live_extra;
    wire config_rejected, request_dropped;
    wire [31:0] snapshot_period_ms = snapshot_period_sec * 32'd1000;
    assign restore_diagonal=ENABLE_DIAGONAL_TRANSITION!=0 && extended_mode && !live_mode[5];
    assign restore_valid = load_done && !fatal_error;
    assign restore_volume = live_volume;
    assign restore_auto_valid = restore_valid;
    assign restore_auto_enabled = live_extra[0];
    assign restore_fade_level = live_extra[2:1];
    assign restore_playback_mode = ENABLE_PLAY_OPTIONS!=0 && live_extra[4:3]<=2 ? live_extra[4:3] : 2'd0;
    assign restore_main_keys_music = ENABLE_PLAY_OPTIONS!=0 && (extended_mode ? live_mode[1:0]==1 : live_extra[5]);
    assign restore_main_keys_thumbnail=extended_mode && live_mode[1:0]==2;
    assign restore_audio_image_bind=ENABLE_AUDIO_IMAGE_BIND!=0 && extended_mode && live_mode[4];
    assign restore_progress_visible=ENABLE_AUDIO_PROGRESS!=0 && (!extended_mode || !live_mode[6]);
    assign restore_thumbnail_transparency=extended_mode ? live_mode[3:2]^2'd2 : 2'd2;
    // Old extension bits 7:6 are zero: XOR 2 restores the default 50%.
    assign restore_menu_transparency=ENABLE_MENU_TRANSPARENCY!=0 ? live_extra[7:6]^2'd2 : 2'd2;
    wire [1:0] transparency_code=ENABLE_MENU_TRANSPARENCY!=0 ? menu_transparency^2'd2 : 2'd0;
    assign save_busy = state != 0;
    player_config_persistence #(
        .ENABLE_FULL_CONFIG_SAVE(ENABLE_FULL_CONFIG_SAVE),.ENABLE_DIAGONAL_TRANSITION(ENABLE_DIAGONAL_TRANSITION),.ENABLE_EXTENDED_MODE(ENABLE_THUMB_TRANSPARENCY),.ENABLE_AUDIO_PROGRESS(ENABLE_AUDIO_PROGRESS),.ENABLE_AUDIO_IMAGE_BIND(ENABLE_AUDIO_IMAGE_BIND),
        .SPI_CLK_DIV(CLK_HZ < 8000000 ? 2 : CLK_HZ / 4000000), // mode 0, 2 MHz SCLK
        .STARTUP_CYCLES(CLK_HZ / 100), .WAKE_CYCLES(CLK_HZ < 100000 ? 1 : CLK_HZ / 100000),
        .CS_HIGH_CYCLES(10), .POLL_INTERVAL_CYCLES(CLK_HZ / 10000),
        .ERASE_TIMEOUT_CYCLES(CLK_HZ * 5), .PROGRAM_TIMEOUT_CYCLES(CLK_HZ / 10),
        .CLKS_PER_MS(CLK_HZ / 1000), .DEFAULT_PERIOD_MS(3000), .DEFAULT_VOLUME(128)
    ) u_service (
        .clk(clk), .rst_n(~rst), .cfg_update_valid(state == 1),
        .cfg_period_ms(snapshot_period_ms), .cfg_volume(snapshot),
        .cfg_mode(snapshot_mode), .cfg_extra(snapshot_extra),.cfg_ui(snapshot_ui),.live_ui(live_ui),
        .save_request(state == 2), .service_ready(ready), .busy(),
        .load_done(load_done), .save_done(save_done), .apply_valid(),
        .config_rejected(config_rejected), .fatal_error(fatal_error), .error_code(),
        .request_dropped(request_dropped), .stored_config_valid(stored_valid),
        .active_version(active_version), .live_period_ms(live_period_ms), .live_period_cycles(),
        .live_volume(live_volume), .live_mode(live_mode), .live_extra(live_extra),
        .jedec_id(), .status1(), .status2(), .status3(),
        .flash_miso(flash_miso), .flash_cs_n(flash_cs_n), .flash_sclk(flash_sclk),
        .flash_mosi(flash_mosi), .flash_wp_n(flash_wp_n), .flash_hold_n(flash_hold_n)
    );
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= 0; mode_q <= 0; snapshot <= 128;
            snapshot_period_sec <= 6'd3;
            snapshot_extra <= 8'h02;snapshot_mode<=0;snapshot_ui<=24'hff8007;
            restore_period_valid <= 0; restore_period_sec <= 6'd3;
            restore_remainder <= 0; restore_count <= 0; restore_pending <= 0;
            save_status <= 0; expected_version <= 0;
        end else begin
            mode_q <= save_mode;
            restore_period_valid <= 0;
            if (load_done && !fatal_error) begin
                restore_remainder <= live_period_ms;
                restore_count <= 0;
                restore_pending <= 1;
            end else if (restore_pending) begin
                if (restore_remainder >= 1000 && restore_count < 30) begin
                    restore_remainder <= restore_remainder - 32'd1000;
                    restore_count <= restore_count + 1'b1;
                end else begin
                    restore_period_sec <= restore_count == 0 ? 6'd3 : restore_count;
                    restore_period_valid <= 1;
                    restore_pending <= 0;
                end
            end
            if (save_mode && !mode_q && state == 0) save_status <= 0;
            case (state)
                0: if (save_event && save_mode) begin
                    if (!ready || fatal_error) save_status <= 3;
                    else begin
                        snapshot_mode<=ENABLE_THUMB_TRANSPARENCY!=0 ?
                            {((ENABLE_AUDIO_IMAGE_BIND!=0 && audio_image_bind ? 4'hb : 4'ha) ^ (ENABLE_DIAGONAL_TRANSITION!=0 && diagonal_selected ? 4'h2 : 4'h0) | (ENABLE_AUDIO_PROGRESS!=0 && !progress_visible ? 4'h4 : 4'h0)),thumbnail_transparency^2'd2,main_keys_thumbnail ? 2'd2 : main_keys_music ? 2'd1 : 2'd0} : 8'd0;
                        snapshot <= volume;
                        snapshot_ui<=ENABLE_FULL_CONFIG_SAVE!=0 ? {brightness,contrast,3'd0,
                            main_keys_thumbnail ? 2'd2 : main_keys_music ? 2'd1 : 2'd0,source_wav,caption_enabled,visual_enabled} : 24'hff8007;
                        snapshot_period_sec <= period_sec;
                        snapshot_extra <= ENABLE_PLAY_OPTIONS!=0 ?
                            {transparency_code,main_keys_music,playback_mode,fade_level,auto_enabled} :
                            {transparency_code,3'd0,fade_level,auto_enabled};
                        expected_version <= active_version + 1'b1;
                        save_status <= 1;
                        state <= 1;
                    end
                end
                1: state <= 2;
                2: state <= 3;
                3: begin
                    if (fatal_error || config_rejected || request_dropped) begin
                        save_status <= 3; state <= 0;
                    end else if (save_done) begin
                        save_status <= stored_valid && live_extra == snapshot_extra &&
                                       live_volume == snapshot && live_mode == snapshot_mode &&
                                       live_period_ms == snapshot_period_ms &&
                                       (ENABLE_FULL_CONFIG_SAVE==0 || live_ui==snapshot_ui) &&
                                       active_version == expected_version ? 2 : 3;
                        state <= 0;
                    end
                end
            endcase
        end
    end
endmodule
