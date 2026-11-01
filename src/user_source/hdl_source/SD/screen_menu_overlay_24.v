`timescale 1ns/1ps

// Pixel-aligned menu layer after the existing status OSD. Reconstruct the
// active line with the same DE/VS bundle; no video clock is added.
module screen_menu_overlay_24 #(parameter integer ENABLE_PLAY_CONTROL=0,
    parameter integer ENABLE_PLAY_OPTIONS=0,
    parameter integer ENABLE_AUDIO_VISUAL=0,
    parameter integer ENABLE_PICTURE_ADJUST=0,
    parameter integer COMPACT_MENU=0,
    parameter integer ENABLE_THUMBNAILS=0,
    parameter integer DIRECTORY_LAYOUT=0,
    parameter integer RESIDENT_THUMBNAILS=0,
    parameter integer FULLSCREEN_THUMBNAILS=0,
    parameter integer ENABLE_MENU_TRANSPARENCY=0,
    parameter integer STRONG_THUMB_BORDER=0,
    parameter integer DEMO_MENU=0,
    parameter integer ENABLE_DIAGONAL_TRANSITION=0,
    parameter integer ENABLE_AUDIO_PROGRESS=0,
    parameter integer ENABLE_AUDIO_IMAGE_BIND=0,
    parameter integer ENABLE_CAPTION=0,
    parameter integer FIXED_OPAQUE_THUMBNAILS=0,
    parameter integer MENU_ITEM_BITS=(ENABLE_AUDIO_IMAGE_BIND!=0 || ENABLE_AUDIO_PROGRESS!=0 || ENABLE_CAPTION!=0) ? 3 : 2,
    parameter integer ENABLE_SHARED_SCALING_RAM=0,
    parameter integer ENABLE_SW4_THUMBNAILS=0,
    parameter integer ENABLE_CLOCK_TIMER=0,
    parameter integer ENABLE_SHARED_LABEL_ROM=0,
    parameter integer ENABLE_LOW_POWER_MENU=0) (
    input wire clk,rst_n,vsync,de,
    input wire [9:0] pixel_x,
    input wire [23:0] rgb_in,
    input wire menu_open,menu_level,
    input wire [1:0] menu_group,
    input wire [MENU_ITEM_BITS-1:0] menu_item,
    input wire diagonal_selected,
    input wire audio_image_bind,
    input wire progress_visible,
    input wire caption_enabled,
    input wire auto_enabled,source_wav,
    input wire audio_paused,audio_ended,
    input wire [1:0] playback_mode,
    input wire main_keys_music,main_keys_thumbnail,
    input wire [5:0] period_sec,
    input wire [1:0] fade_level,
    input wire [7:0] volume,
    input wire [3:0] track_number,track_count,
    input wire [1:0] save_status,
    output wire [23:0] rgb_out,
    output wire menu_visible,
    input wire visual_enabled,
    input wire image_page,
    input wire [7:0] brightness,contrast,
    input wire [1:0] menu_transparency,
    input wire [1:0] thumbnail_transparency,
    input wire thumbnail_view,thumbnail_waiting,
    input wire [4:0] thumbnail_focus,
    input wire [5:0] thumbnail_count,
    input wire [3:0] thumbnail_ready,thumbnail_failed,
    input wire progress_valid,progress_long_time,
    input wire [23:0] progress_elapsed_bcd,progress_total_bcd,
    input wire [4:0] progress_fill_pixels,
    output wire [6:0] caption_font_address,
    input wire [7:0] caption_font_byte,
    input wire clock_stable,
    input wire [1:0] clock_edit_selection,
    input wire [23:0] clock_time,
    input wire clock_valid,clock_timer_enabled,clock_edit_minutes,
    input wire clock_display_enabled,
    input wire [15:0] clock_timer,clock_edit,
    input wire label_grant,label_response_valid,
    input wire [6:0] label_glyph,
    output wire label_request,
    output wire [8:0] label_address
);
    reg [11:0] line_y;
    reg de_q,vs_q;
    // Compact menu uses active-pixel coordinates reconstructed from the same
    // DE bundle as its line counter. HDMI packet coordinates remain untouched.
    reg [9:0] active_x;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) active_x<=0;
        else if(!de) active_x<=0;
        else active_x<=active_x+1'b1;
    end
    wire frame_start=vs_q && !vsync;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin line_y<=0;de_q<=0;vs_q<=1;end
        else begin
            de_q<=de;vs_q<=vsync;
            if(!vsync) line_y<=0;
            else if(de_q && !de) line_y<=line_y+1'b1;
        end
    end
    reg [1:0] clock_edit_owner_q;
    reg [23:0] clock_time_q;
    reg [15:0] clock_timer_q,clock_edit_q;
    reg clock_valid_q,clock_timer_enabled_q,clock_edit_minutes_q;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            clock_time_q<=0;clock_timer_q<=0;clock_edit_q<=0;clock_edit_owner_q<=0;
            clock_valid_q<=0;clock_timer_enabled_q<=0;clock_edit_minutes_q<=0;
        end else if(frame_start && (ENABLE_CLOCK_TIMER==0 || clock_stable)) begin
            clock_time_q<=clock_time;clock_timer_q<=clock_timer;clock_edit_q<=clock_edit;clock_edit_owner_q<=clock_edit_selection;
            clock_valid_q<=clock_valid;clock_timer_enabled_q<=clock_timer_enabled;
            clock_edit_minutes_q<=clock_edit_minutes;
        end
    end
    wire [23:0] progress_rgb;
    generate if(ENABLE_AUDIO_PROGRESS!=0) begin : g_progress_overlay
        audio_progress_overlay #(.ENABLE_CLOCK_TIMER(ENABLE_CLOCK_TIMER),.ENABLE_CLOCK_DISPLAY_CONTROL(ENABLE_LOW_POWER_MENU)) progress_layer (
            .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.de(de),
            .enable(progress_visible),.menu_open(menu_open),.source_wav(source_wav),.valid(progress_valid),
            .paused(audio_paused),.ended(audio_ended),.pixel_x(active_x),.pixel_y(line_y),.rgb_in(rgb_in),
            .elapsed_bcd(progress_elapsed_bcd),.total_bcd(progress_total_bcd),.long_time(progress_long_time),
            .fill_pixels(progress_fill_pixels),.clock_display_enabled(clock_display_enabled),.clock_time(clock_time_q),.clock_valid(clock_valid_q),.rgb_out(progress_rgb));
    end else begin : g_no_progress_overlay
        assign progress_rgb=rgb_in;
    end endgenerate
    screen_menu_overlay #(.ENABLE_PLAY_CONTROL(ENABLE_PLAY_CONTROL),.ENABLE_PLAY_OPTIONS(ENABLE_PLAY_OPTIONS),
        .ENABLE_AUDIO_VISUAL(ENABLE_AUDIO_VISUAL),.ENABLE_PICTURE_ADJUST(ENABLE_PICTURE_ADJUST),.COMPACT_MENU(COMPACT_MENU),.ENABLE_THUMBNAILS(ENABLE_THUMBNAILS),.DIRECTORY_LAYOUT(DIRECTORY_LAYOUT),.RESIDENT_THUMBNAILS(RESIDENT_THUMBNAILS),.FULLSCREEN_THUMBNAILS(FULLSCREEN_THUMBNAILS),.ENABLE_MENU_TRANSPARENCY(ENABLE_MENU_TRANSPARENCY),.STRONG_THUMB_BORDER(STRONG_THUMB_BORDER),.DEMO_MENU(DEMO_MENU),.ENABLE_AUDIO_IMAGE_BIND(ENABLE_AUDIO_IMAGE_BIND),.ENABLE_DIAGONAL_TRANSITION(ENABLE_DIAGONAL_TRANSITION),.ENABLE_AUDIO_PROGRESS(ENABLE_AUDIO_PROGRESS),.ENABLE_CAPTION(ENABLE_CAPTION),.FIXED_OPAQUE_THUMBNAILS(FIXED_OPAQUE_THUMBNAILS),.MENU_ITEM_BITS(MENU_ITEM_BITS),.ENABLE_SHARED_SCALING_RAM(ENABLE_SHARED_SCALING_RAM),.ENABLE_SW4_THUMBNAILS(ENABLE_SW4_THUMBNAILS),.ENABLE_CLOCK_TIMER(ENABLE_CLOCK_TIMER),.ENABLE_SHARED_LABEL_ROM(ENABLE_SHARED_LABEL_ROM),.ENABLE_LOW_POWER_MENU(ENABLE_LOW_POWER_MENU)) u_menu (
        .label_request(label_request),.label_address(label_address),.label_grant(label_grant),
        .label_response_valid(label_response_valid),.label_glyph(label_glyph),
        .caption_font_address(caption_font_address),.caption_font_byte(caption_font_byte),
        .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.de(de),
        .pixel_x(COMPACT_MENU!=0 ? active_x : pixel_x),.pixel_y(line_y),.rgb_in(progress_rgb),
        .menu_open(menu_open),.menu_level(menu_level),
        .menu_group(menu_group),.menu_item(menu_item),.diagonal_selected(diagonal_selected),.audio_image_bind(audio_image_bind),.progress_visible(progress_visible),.caption_enabled(caption_enabled),
        .auto_enabled(auto_enabled),.source_wav(source_wav),
        .audio_paused(audio_paused),.audio_ended(audio_ended),
        .playback_mode(playback_mode),.main_keys_music(main_keys_music),.main_keys_thumbnail(main_keys_thumbnail),
        .period_sec(period_sec),.fade_level(fade_level),.volume(volume),
        .track_number(track_number),.track_count(track_count),
        .clock_display_enabled(clock_display_enabled),.clock_time(clock_time_q),.clock_valid(clock_valid_q),.clock_timer(clock_timer_q),
        .clock_edit_owner(clock_edit_owner_q),.clock_edit(clock_edit_q),.clock_timer_enabled(clock_timer_enabled_q),.clock_edit_minutes(clock_edit_minutes_q),
        .save_status(save_status),.visual_enabled(visual_enabled),
        .image_page(image_page),.brightness(brightness),.contrast(contrast),.menu_transparency(menu_transparency),.thumbnail_transparency(thumbnail_transparency),.rgb_out(rgb_out),
        .thumbnail_view(thumbnail_view),.thumbnail_waiting(thumbnail_waiting),
        .thumbnail_focus(thumbnail_focus),.thumbnail_count(thumbnail_count),
        .thumbnail_ready(thumbnail_ready),.thumbnail_failed(thumbnail_failed),
        .menu_visible(menu_visible)
    );
endmodule
