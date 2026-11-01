`timescale 1ns/1ps

// Hierarchical HDMI menu. KEY4 short: next row; KEY4 long: enter/back.
// KEY2/KEY3 edit the selected item at level 2. The active picture keeps
// playing behind the menu, and the Flash record format is unchanged.
module screen_menu_controller #(
    parameter integer CLK_FREQ_HZ = 100000000,
    parameter integer LONG_PRESS_MS = 500,
    parameter integer REPEAT_MS = 50,
    parameter integer MENU_TIMEOUT_MS = 10000,
    parameter integer ENABLE_PLAY_CONTROL = 0,
    parameter integer ENABLE_PLAY_OPTIONS = 0,
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
    parameter integer ENABLE_DIAGONAL_TRANSITION=0,
    parameter integer ENABLE_AUDIO_PROGRESS = 0,
    parameter integer ENABLE_CAPTION = 0,
    parameter integer FIXED_OPAQUE_THUMBNAILS=0,
    parameter integer ENABLE_AUDIO_IMAGE_BIND = 0,
    parameter integer MENU_ITEM_BITS = (ENABLE_AUDIO_IMAGE_BIND!=0 || ENABLE_AUDIO_PROGRESS!=0 || ENABLE_CAPTION!=0) ? 3 : 2,
    parameter integer ENABLE_SW4_THUMBNAILS=0,
    parameter integer ENABLE_FULL_CONFIG_SAVE=0,
    parameter integer ENABLE_CLOCK_TIMER=0,
    parameter integer ENABLE_LOW_POWER_MENU=0
) (
    input wire clk,rst,
    input wire key_plus_n,key_minus_n,key_mode_n,
    input wire key_confirm_n,
    input wire [1:0] main_keys_sw,
    input wire auto_play_enabled, // Actual autoplay state from navigation policy
    input wire save_busy,
    input wire playback_ended,
    input wire restore_valid,
    input wire [7:0] restore_volume,
    input wire [23:0] restore_ui,
    input wire restore_period_valid,
    input wire [5:0] restore_period_sec,
    input wire [1:0] restore_fade_level,
    input wire [1:0] restore_playback_mode,
    input wire restore_main_keys_music,
    input wire [1:0] restore_menu_transparency,
    input wire [1:0] restore_thumbnail_transparency,
    input wire restore_main_keys_thumbnail,
    input wire restore_audio_image_bind,
    input wire restore_progress_visible,
    output reg next_event,prev_event,auto_event,auto_value,
    output reg [7:0] volume,
    output reg [5:0] period_sec,
    output reg [1:0] fade_level,
    output reg period_change_valid,save_event,
    output reg source_wav,track_next_event,track_prev_event,
    output reg audio_paused,replay_event,
    output reg [1:0] playback_mode,
    output reg main_keys_music,
    output reg main_keys_thumbnail,
    output wire play_mode,
    output wire auto_mode,volume_mode,period_mode,fade_mode,
    output wire save_mode,source_mode,track_mode,
    output reg menu_open,menu_level,
    output reg [1:0] menu_group,
    output reg [MENU_ITEM_BITS-1:0] menu_item,
    input wire restore_diagonal,
    output reg diagonal_selected,
    output reg audio_image_bind,
    output reg progress_visible,
    output reg caption_enabled,
    output reg visual_enabled,
    output reg image_page,
    output reg [1:0] menu_transparency,
    output reg [1:0] thumbnail_transparency,
    output reg [7:0] brightness,contrast,
    input wire thumb_mode,
    output reg thumb_enter,
    output wire thumb_next,thumb_prev,thumb_confirm,thumb_back,
    input wire thumbnail_switch,
    input wire display_sleep,
    output reg [2:0] clock_command
);
    wire plus_short,plus_long,minus_short,minus_long,mode_short,mode_long;
    wire plus_n,minus_n,mode_n;
    key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.LONG_PRESS_MS(LONG_PRESS_MS)) u_plus (
        .clk(clk),.rst(rst),.button_in(key_plus_n),
        .button_stable_out(plus_n),.short_press(plus_short),.long_press(plus_long));
    key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.LONG_PRESS_MS(LONG_PRESS_MS)) u_minus (
        .clk(clk),.rst(rst),.button_in(key_minus_n),
        .button_stable_out(minus_n),.short_press(minus_short),.long_press(minus_long));
    key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.LONG_PRESS_MS(LONG_PRESS_MS)) u_mode (
        .clk(clk),.rst(rst),.button_in(key_mode_n),
        .button_stable_out(mode_n),.short_press(mode_short),.long_press(mode_long));

    wire confirm_n,confirm_short,confirm_long;
    generate if(ENABLE_CONFIRM_KEY!=0) begin : g_confirm_key
        key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.LONG_PRESS_MS(LONG_PRESS_MS)) u_confirm (
            .clk(clk),.rst(rst),.button_in(key_confirm_n),
            .button_stable_out(confirm_n),.short_press(confirm_short),.long_press(confirm_long));
    end else begin : g_no_confirm_key
        assign confirm_n=1'b1;assign confirm_short=0;assign confirm_long=0;
    end endgenerate
    localparam integer SWITCH_CYCLES=(CLK_FREQ_HZ/1000)*20;
    localparam integer SWITCH_WIDTH=SWITCH_CYCLES<2 ? 1 : $clog2(SWITCH_CYCLES);
    (* async_reg="true" *) reg [2:0] main_sw_sync0,main_sw_sync1;
    reg [2:0] main_sw_candidate,main_sw_stable;
    reg [SWITCH_WIDTH-1:0] main_sw_count;
    reg main_sw_valid,main_sw_event,main_keys_sw_event;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            main_sw_sync0<=0;main_sw_sync1<=0;main_sw_candidate<=0;
            main_sw_stable<=0;main_sw_count<=0;main_sw_valid<=0;main_sw_event<=0;main_keys_sw_event<=0;
        end else if(ENABLE_SWITCH_MODE!=0) begin
            main_sw_event<=0;main_keys_sw_event<=0;
            main_sw_sync0<={ENABLE_SW4_THUMBNAILS!=0 && thumbnail_switch,main_keys_sw};main_sw_sync1<=main_sw_sync0;
            if(main_sw_sync1!=main_sw_candidate) begin
                main_sw_candidate<=main_sw_sync1;main_sw_count<=0;
            end else if(main_sw_count<SWITCH_CYCLES-1)
                main_sw_count<=main_sw_count+1'b1;
            else begin
                main_sw_event<=main_sw_valid && main_sw_stable!=main_sw_candidate;
                main_keys_sw_event<=main_sw_valid ? main_sw_stable[1:0]!=main_sw_candidate[1:0] : main_sw_candidate[1:0]==2'd2;
                main_sw_stable<=main_sw_candidate;main_sw_valid<=1;
            end
        end
    end
    // 00 picture, 01 music, 10 thumbnails; 11 is reserved/picture.
    wire switch_music=main_sw_stable[1:0]==2'd1;
    wire switch_thumbnail=main_sw_stable[1:0]==2'd2;
    wire switch_changed=ENABLE_SWITCH_MODE!=0 && (DEMO_MENU!=0 ? main_sw_event :
        main_sw_valid && (main_keys_music!=switch_music || main_keys_thumbnail!=switch_thumbnail));
    wire confirm_press=confirm_short || confirm_long;
    reg confirm_armed;
    reg [2:0] confirm_release_count;
    wire confirm_action=ENABLE_CONFIRM_KEY!=0 && confirm_armed && confirm_press &&
        !save_busy && plus_n && minus_n && mode_n && !switch_changed;
    always @(posedge clk or posedge rst) begin
        if(rst) begin confirm_armed<=0;confirm_release_count<=0;end
        else if(save_busy || !plus_n || !minus_n || !mode_n ||
                mode_short || mode_long || switch_changed || confirm_press) begin
            confirm_armed<=0;confirm_release_count<=0;
        end else if(confirm_n) begin
            if(confirm_release_count==7) confirm_armed<=1;
            else confirm_release_count<=confirm_release_count+1'b1;
        end else confirm_release_count<=0;
    end

    localparam integer REPEAT_CYCLES=(CLK_FREQ_HZ/1000)*REPEAT_MS;
    localparam integer TIMEOUT_CYCLES=(CLK_FREQ_HZ/1000)*MENU_TIMEOUT_MS;
    localparam integer REPEAT_WIDTH=REPEAT_CYCLES<2 ? 1 : $clog2(REPEAT_CYCLES);
    localparam integer TIMEOUT_WIDTH=TIMEOUT_CYCLES<2 ? 1 : $clog2(TIMEOUT_CYCLES);
    reg plus_repeat,minus_repeat,blocked;
    reg [REPEAT_WIDTH-1:0] plus_count,minus_count;
    reg [TIMEOUT_WIDTH-1:0] menu_idle_count;
    reg [2:0] release_count;
    // Isolated exact-cycle menu timer subset; other parameters remain binary.
    localparam integer USE_SHIFT_MENU_COUNTERS=CLK_FREQ_HZ==50_000_000 &&
        REPEAT_MS==50 && MENU_TIMEOUT_MS==10000;
    localparam [REPEAT_WIDTH-1:0] REPEAT_START=USE_SHIFT_MENU_COUNTERS ? 1 : 0;
    // The guarded menu edits only one held +/- key; keep legacy counters below.
    localparam integer USE_SHARED_MENU_REPEAT=USE_SHIFT_MENU_COUNTERS!=0 &&
        ENABLE_LOW_POWER_MENU!=0 && ENABLE_CLOCK_TIMER!=0 && DEMO_MENU==2 && ENABLE_SW4_THUMBNAILS!=0;
    reg [REPEAT_WIDTH-1:0] shared_repeat_count;
    wire shared_repeat_done=shared_repeat_count==22'h12c119;
    // Exact500,000,000-cycle idle phase; legacy parameter sets stay binary.
    localparam integer USE_SHIFT_MENU_IDLE=USE_SHARED_MENU_REPEAT!=0;
    localparam [TIMEOUT_WIDTH-1:0] MENU_IDLE_START=USE_SHIFT_MENU_IDLE ? 1 : 0;
    wire menu_idle_done=USE_SHIFT_MENU_IDLE ? menu_idle_count==29'h1e4f13c5 : menu_idle_count>=TIMEOUT_CYCLES-1;
    wire [TIMEOUT_WIDTH-1:0] menu_idle_next;
    generate if(USE_SHIFT_MENU_IDLE!=0) begin : g_shift_menu_idle
        assign menu_idle_next={menu_idle_count[0]^menu_idle_count[2],menu_idle_count[TIMEOUT_WIDTH-1:1]};
    end else begin : g_binary_menu_idle
        assign menu_idle_next=menu_idle_count+1'b1;
    end endgenerate
    wire [REPEAT_WIDTH-1:0] plus_count_next,minus_count_next;
    wire plus_count_done=USE_SHARED_MENU_REPEAT ? shared_repeat_done : USE_SHIFT_MENU_COUNTERS ? plus_count==22'h12c119 : plus_count==REPEAT_CYCLES-1;
    wire minus_count_done=USE_SHARED_MENU_REPEAT ? shared_repeat_done : USE_SHIFT_MENU_COUNTERS ? minus_count==22'h12c119 : minus_count==REPEAT_CYCLES-1;
    generate if(USE_SHIFT_MENU_COUNTERS!=0) begin : g_shift_menu_repeat
        assign plus_count_next={plus_count[0]^plus_count[1],plus_count[REPEAT_WIDTH-1:1]};
        assign minus_count_next={minus_count[0]^minus_count[1],minus_count[REPEAT_WIDTH-1:1]};
    end else begin : g_binary_menu_repeat
        assign plus_count_next=plus_count+1'b1;
        assign minus_count_next=minus_count+1'b1;
    end endgenerate
    wire plus_tick=plus_repeat && !plus_n && plus_count_done;
    wire minus_tick=minus_repeat && !minus_n && minus_count_done;
    // Mode 2 uses the otherwise-unused picture-page bit as category bit 2.
    // All existing ports and the frame snapshot keep their widths/positions.
    localparam integer SEVEN_MENU=(DEMO_MENU==2);
    localparam integer LOW_POWER_MENU=ENABLE_LOW_POWER_MENU!=0 && ENABLE_CLOCK_TIMER!=0 && SEVEN_MENU!=0 && ENABLE_SW4_THUMBNAILS!=0;
    wire [2:0] seven_group={image_page,menu_group};
    function [MENU_ITEM_BITS-1:0] seven_last_item;
        input [2:0] category;
        begin case(category)
            0:seven_last_item=2;1:seven_last_item=3;2:seven_last_item=1;
            3:seven_last_item=FIXED_OPAQUE_THUMBNAILS!=0 ? 0 : 1;4:seven_last_item=0;5:seven_last_item=ENABLE_CAPTION!=0 ? 4 : 3;
            6:seven_last_item=LOW_POWER_MENU!=0 ? 2 : ENABLE_CLOCK_TIMER!=0 ? 4 : 2;
            7:seven_last_item=LOW_POWER_MENU!=0 ? 3 : 0;
            default:seven_last_item=0;
        endcase end
    endfunction
    wire selected_value=menu_open && menu_level;
    wire clock_asleep=ENABLE_CLOCK_TIMER!=0 && display_sleep;
    wire clock_setting=ENABLE_CLOCK_TIMER!=0 && SEVEN_MENU!=0 && selected_value &&
        (LOW_POWER_MENU!=0 ? seven_group==7 && menu_item<2 : seven_group==6 && menu_item>=3);
    wire clock_cancel_setting=LOW_POWER_MENU!=0 && selected_value && seven_group==7 && menu_item==2;
    wire clock_display_setting=LOW_POWER_MENU!=0 && selected_value && seven_group==7 && menu_item==3;
    always @(posedge clk or posedge rst) begin
        if(rst) clock_command<=0;
        else if(ENABLE_CLOCK_TIMER!=0 && !save_busy) begin
            if(clock_asleep && confirm_short || !clock_asleep && (clock_setting || clock_display_setting) && confirm_action)
                clock_command<={~clock_command[2],2'd2};
            else if(!clock_asleep && clock_cancel_setting && confirm_action)
                clock_command<={~clock_command[2],2'd3};
            else if(!clock_asleep && (clock_setting || clock_display_setting) && !blocked &&
                    (LOW_POWER_MENU==0 || (mode_n && confirm_n && !switch_changed && (plus_n || minus_n)))) begin
                if(LOW_POWER_MENU==0 && menu_item==4 && minus_long) clock_command<={~clock_command[2],2'd3};
                else if((LOW_POWER_MENU!=0 ? plus_edit : plus_short) && !(LOW_POWER_MENU!=0 ? minus_edit : minus_short))
                    clock_command<={~clock_command[2],2'd0};
                else if((LOW_POWER_MENU!=0 ? minus_edit : minus_short) && !(LOW_POWER_MENU!=0 ? plus_edit : plus_short))
                    clock_command<={~clock_command[2],2'd1};
            end
        end
    end

    wire thumb_keys=FULLSCREEN_THUMBNAILS!=0 ? main_keys_thumbnail : !main_keys_music;
    assign thumb_next=!clock_asleep && ENABLE_THUMBNAILS!=0 && thumb_mode && !menu_open && (RESIDENT_THUMBNAILS==0 || thumb_keys) && !blocked && confirm_n && !switch_changed && !save_busy && plus_short;
    assign thumb_prev=!clock_asleep && ENABLE_THUMBNAILS!=0 && thumb_mode && !menu_open && (RESIDENT_THUMBNAILS==0 || thumb_keys) && !blocked && confirm_n && !switch_changed && !save_busy && minus_short;
    assign thumb_confirm=!clock_asleep && ENABLE_THUMBNAILS!=0 && thumb_mode && !menu_open &&
        (ENABLE_CONFIRM_KEY!=0 ? (RESIDENT_THUMBNAILS==0 || thumb_keys) && confirm_action :
         RESIDENT_THUMBNAILS==0 && !save_busy && plus_n && minus_n && mode_short);
    assign thumb_back=!clock_asleep && ENABLE_THUMBNAILS!=0 && thumb_mode && RESIDENT_THUMBNAILS==0 && !save_busy && plus_n && minus_n && mode_long;
    wire caption_edit=ENABLE_CAPTION!=0 && SEVEN_MENU!=0 && selected_value && seven_group==5 && menu_item==4;
    wire brightness_edit=SEVEN_MENU!=0 ? (ENABLE_PICTURE_ADJUST!=0 && selected_value && seven_group==5 && menu_item==0) :
        (ENABLE_PICTURE_ADJUST!=0 && selected_value && (DEMO_MENU!=0 ? menu_group==1 : menu_group==0 && image_page) && menu_item==0);
    wire contrast_edit=SEVEN_MENU!=0 ? (ENABLE_PICTURE_ADJUST!=0 && selected_value && seven_group==5 && menu_item==1) :
        (ENABLE_PICTURE_ADJUST!=0 && selected_value && (DEMO_MENU!=0 ? menu_group==1 : menu_group==0 && image_page) && menu_item==1);
    wire picture_reset=SEVEN_MENU!=0 ? (ENABLE_PICTURE_ADJUST!=0 && selected_value && seven_group==5 && menu_item==3) :
        (ENABLE_PICTURE_ADJUST!=0 && selected_value && (DEMO_MENU!=0 ? menu_group==1 : menu_group==0 && image_page) && menu_item==2);
    wire transparency_edit=SEVEN_MENU!=0 ? (ENABLE_MENU_TRANSPARENCY!=0 && selected_value && seven_group==6 && menu_item==1) :
        (ENABLE_MENU_TRANSPARENCY!=0 && selected_value && (DEMO_MENU!=0 ? menu_group==3 && menu_item==1 : menu_group==0 && image_page && menu_item==3));
    wire thumbnail_transparency_edit=ENABLE_SW4_THUMBNAILS==0 && FIXED_OPAQUE_THUMBNAILS==0 && (SEVEN_MENU!=0 ? (ENABLE_THUMB_TRANSPARENCY!=0 && selected_value && seven_group==3 && menu_item==1) :
        (ENABLE_THUMB_TRANSPARENCY!=0 && selected_value && menu_group==3 && menu_item==2));
    wire thumbnails_edit=ENABLE_SW4_THUMBNAILS==0 && (SEVEN_MENU!=0 ? (ENABLE_THUMBNAILS!=0 && selected_value && seven_group==3 && menu_item==0) :
        (ENABLE_THUMBNAILS!=0 && selected_value && menu_group==0 && !image_page && menu_item==3));
    wire progress_edit=SEVEN_MENU!=0 ? (ENABLE_AUDIO_PROGRESS!=0 && selected_value && seven_group==1 && menu_item==2) :
        (ENABLE_AUDIO_PROGRESS!=0 && selected_value && menu_group==3 && menu_item==3);
    wire diagonal_edit=SEVEN_MENU!=0 ? (ENABLE_DIAGONAL_TRANSITION!=0 && selected_value && seven_group==2 && menu_item==0) :
        (ENABLE_DIAGONAL_TRANSITION!=0 && selected_value && menu_group==0 && menu_item==5);
    wire binding_edit=SEVEN_MENU!=0 ? (ENABLE_AUDIO_IMAGE_BIND!=0 && selected_value && seven_group==0 && menu_item==0) :
        (ENABLE_AUDIO_IMAGE_BIND!=0 && selected_value && menu_group==0 && menu_item==4);
    wire edit_repeat=volume_mode || period_mode || fade_mode || brightness_edit || contrast_edit || (LOW_POWER_MENU!=0 && clock_setting);
    wire plus_edit=plus_short || (edit_repeat && (plus_long || plus_tick));
    wire minus_edit=minus_short || (edit_repeat && (minus_long || minus_tick));

    generate if(USE_SHARED_MENU_REPEAT!=0) begin : g_shared_menu_repeat
        always @(posedge clk or posedge rst) begin
            if(rst) shared_repeat_count<=REPEAT_START;
            else if(clock_asleep || save_busy || !mode_n || !confirm_n || confirm_press ||
                    switch_changed || mode_short || mode_long || (!plus_n && !minus_n) ||
                    blocked || !menu_open || !menu_level || !edit_repeat)
                shared_repeat_count<=REPEAT_START;
            else if((!plus_n && plus_repeat && !plus_long) ||
                    (!minus_n && minus_repeat && !minus_long)) begin
                if(shared_repeat_done) shared_repeat_count<=REPEAT_START;
                else shared_repeat_count<={shared_repeat_count[0]^shared_repeat_count[1],shared_repeat_count[REPEAT_WIDTH-1:1]};
            end else shared_repeat_count<=REPEAT_START;
        end
    end endgenerate

    // Only one numeric row is edited; keep the original clock and guards.
    wire [7:0] edit_value=volume_mode ? volume : brightness_edit ? brightness : contrast;
    wire [7:0] edit_delta=minus_edit ? 8'hff : 8'd1;
    wire [7:0] edit_result=edit_value+edit_delta;

    // Picture: AUTO, PRD, FADE. Audio: SOURCE, TRACK, VOL. System: SAVE.
    assign auto_mode=SEVEN_MENU!=0 ? (selected_value && seven_group==0 && menu_item==1) :
        (selected_value && menu_group==0 && menu_item==0 && !image_page);
    assign period_mode=SEVEN_MENU!=0 ? (selected_value && seven_group==0 && menu_item==2 && !(ENABLE_AUDIO_IMAGE_BIND!=0 && audio_image_bind)) :
        (selected_value && menu_group==0 && menu_item==1 && !image_page &&
        !(ENABLE_AUDIO_IMAGE_BIND!=0 && audio_image_bind));
    assign fade_mode=SEVEN_MENU!=0 ? (selected_value && seven_group==2 && menu_item==1) :
        (selected_value && menu_group==0 && menu_item==2 && !image_page);
    assign source_mode=SEVEN_MENU!=0 ? (selected_value && seven_group==1 && menu_item==0) :
        (selected_value && menu_group==(DEMO_MENU!=0 ? 2 : 1) && menu_item==0);
    assign track_mode=SEVEN_MENU!=0 ? (selected_value && seven_group==1 && menu_item==1) :
        (selected_value && menu_group==(DEMO_MENU!=0 ? 2 : 1) && menu_item==1);
    assign volume_mode=SEVEN_MENU!=0 ? (selected_value && seven_group==5 && menu_item==2) :
        (selected_value && menu_group==(DEMO_MENU!=0 ? 2 : 1) && menu_item==(DEMO_MENU!=0 ? 2 : ENABLE_PLAY_CONTROL!=0 ? 3 : 2));
    assign play_mode=DEMO_MENU==0 && ENABLE_PLAY_CONTROL!=0 && selected_value && menu_group==1 && menu_item==2;
    assign save_mode=SEVEN_MENU!=0 ? (selected_value && seven_group==6 && menu_item==2) :
        (selected_value && menu_group==(DEMO_MENU!=0 ? 3 : 2) && menu_item==(DEMO_MENU!=0 ? (ENABLE_AUDIO_PROGRESS!=0 ? 4 : 3) : 0));
    wire playback_mode_edit=SEVEN_MENU!=0 ? (ENABLE_PLAY_OPTIONS!=0 && selected_value && seven_group==1 && menu_item==3) :
        (ENABLE_PLAY_OPTIONS!=0 && selected_value && (DEMO_MENU!=0 ? menu_group==2 && menu_item==3 : menu_group==2 && menu_item==1));
    wire main_keys_edit=SEVEN_MENU!=0 ? (ENABLE_PLAY_OPTIONS!=0 && selected_value && seven_group==6 && menu_item==0) :
        (ENABLE_PLAY_OPTIONS!=0 && (DEMO_MENU!=0 || ENABLE_SWITCH_MODE==0) && selected_value && (DEMO_MENU!=0 ? menu_group==3 && menu_item==0 : menu_group==2 && menu_item==2));

    wire visual_edit=SEVEN_MENU!=0 ? (ENABLE_AUDIO_VISUAL!=0 && selected_value && seven_group==4 && menu_item==0) :
        (ENABLE_AUDIO_VISUAL!=0 && selected_value && menu_group==(DEMO_MENU!=0 ? 1 : 2) && menu_item==3);

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            menu_open<=0;menu_level<=0;menu_group<=0;menu_item<=0;visual_enabled<=1;progress_visible<=ENABLE_AUDIO_PROGRESS!=0;
            image_page<=0;brightness<=255;contrast<=128;menu_transparency<=2'd2;thumbnail_transparency<=FIXED_OPAQUE_THUMBNAILS!=0 ? 2'd0 : 2'd2;audio_image_bind<=0;thumb_enter<=ENABLE_SW4_THUMBNAILS==0 && RESIDENT_THUMBNAILS!=0;
            diagonal_selected<=0;caption_enabled<=ENABLE_CAPTION!=0;
            volume<=8'd128;period_sec<=6'd3;fade_level<=2'd1;source_wav<=1;
            next_event<=0;prev_event<=0;auto_event<=0;auto_value<=0;
            period_change_valid<=0;save_event<=0;
            track_next_event<=0;track_prev_event<=0;
            audio_paused<=0;replay_event<=0;playback_mode<=0;main_keys_music<=0;main_keys_thumbnail<=0;
            plus_repeat<=0;minus_repeat<=0;plus_count<=REPEAT_START;minus_count<=REPEAT_START;
            menu_idle_count<=MENU_IDLE_START;blocked<=1;release_count<=0;
        end else begin
            next_event<=0;prev_event<=0;auto_event<=0;if(RESIDENT_THUMBNAILS==0) thumb_enter<=0;
            save_event<=0;period_change_valid<=0;
            track_next_event<=0;track_prev_event<=0;replay_event<=0;
            if(restore_valid) begin
                if(ENABLE_FULL_CONFIG_SAVE!=0) begin
                    brightness<=restore_ui[23:16];contrast<=restore_ui[15:8];
                    visual_enabled<=restore_ui[0];caption_enabled<=ENABLE_CAPTION!=0 && restore_ui[1];
                    source_wav<=restore_ui[2];
                end
                if(ENABLE_DIAGONAL_TRANSITION!=0) diagonal_selected<=restore_diagonal;
                if(ENABLE_AUDIO_IMAGE_BIND!=0) audio_image_bind<=restore_audio_image_bind;
                if(ENABLE_AUDIO_PROGRESS!=0) progress_visible<=restore_progress_visible;
                volume<=restore_volume;
                fade_level<=restore_fade_level;
                if(ENABLE_MENU_TRANSPARENCY!=0) menu_transparency<=restore_menu_transparency;
                if(ENABLE_SW4_THUMBNAILS==0 && ENABLE_THUMB_TRANSPARENCY!=0 && FIXED_OPAQUE_THUMBNAILS==0) thumbnail_transparency<=restore_thumbnail_transparency;
                if(ENABLE_PLAY_OPTIONS!=0) begin
                    playback_mode<=restore_playback_mode<=2 ? restore_playback_mode : 2'd0;
                    if(ENABLE_SWITCH_MODE==0 || DEMO_MENU!=0) begin
                        main_keys_music<=restore_main_keys_music;main_keys_thumbnail<=(ENABLE_SW4_THUMBNAILS==0 || ENABLE_FULL_CONFIG_SAVE!=0) && DEMO_MENU!=0 && restore_main_keys_thumbnail;
                        if(ENABLE_SW4_THUMBNAILS==0 && DEMO_MENU!=0 && restore_main_keys_thumbnail) thumb_enter<=1;
                    end
                end
            end
            if(ENABLE_SWITCH_MODE!=0 && (DEMO_MENU!=0 ? (ENABLE_SW4_THUMBNAILS!=0 ? main_keys_sw_event : main_sw_event) : main_sw_valid)) begin
                main_keys_music<=switch_music;main_keys_thumbnail<=switch_thumbnail;
                if(switch_thumbnail) thumb_enter<=1;
            end
            if(restore_period_valid) begin
                period_sec<=restore_period_sec<1 ? 6'd1 :
                            restore_period_sec>30 ? 6'd30 : restore_period_sec;
                period_change_valid<=1;
            end

            if(!clock_asleep && !save_busy && mode_short && !(ENABLE_THUMBNAILS!=0 && thumb_mode && RESIDENT_THUMBNAILS==0)) begin
                menu_idle_count<=MENU_IDLE_START;
                if(!menu_open) begin
                    menu_open<=1;menu_level<=0;menu_group<=0;menu_item<=0;image_page<=0;
                end else if(!menu_level) begin
                    if(SEVEN_MENU!=0) {image_page,menu_group}<=seven_group==6 ? 3'd0 : LOW_POWER_MENU!=0 && seven_group==5 ? 3'd7 :
                        LOW_POWER_MENU!=0 && seven_group==7 ? 3'd6 : ENABLE_SW4_THUMBNAILS!=0 && seven_group==2 ? 3'd4 : seven_group+1'b1;
                    else menu_group<=menu_group==3 ? 2'd0 : menu_group+1'b1;
                end else if(SEVEN_MENU!=0) menu_item<=menu_item==seven_last_item(seven_group) ? 0 : menu_item+1'b1;
                else if(DEMO_MENU!=0) menu_item<=menu_item==((ENABLE_DIAGONAL_TRANSITION!=0 && menu_group==0) ? 5 : (ENABLE_AUDIO_IMAGE_BIND!=0 && menu_group==0 || ENABLE_AUDIO_PROGRESS!=0 && menu_group==3) ? 4 : 3) ? 0 : menu_item+1'b1;
                else if((ENABLE_PICTURE_ADJUST!=0 || ENABLE_THUMBNAILS!=0) && menu_group==0) begin
                    if(menu_item==((ENABLE_THUMBNAILS!=0 && !image_page || ENABLE_MENU_TRANSPARENCY!=0 && image_page) ? 3 : 2)) begin
                        menu_item<=0;image_page<=ENABLE_PICTURE_ADJUST!=0 && !image_page;
                    end
                    else menu_item<=menu_item+1'b1;
                end else if(menu_group==2) menu_item<=
                    menu_item<(ENABLE_AUDIO_VISUAL!=0 ? 3 : ENABLE_PLAY_OPTIONS!=0 ? 2 : 0) ? menu_item+1'b1 : 2'd0;
                else menu_item<=menu_item==(ENABLE_PLAY_CONTROL!=0 && menu_group==1 ? 3 : 2) ?
                                2'd0 : menu_item+1'b1;
            end else if(!clock_asleep && !save_busy && (mode_long || (confirm_action && !menu_level)) && menu_open && !(ENABLE_THUMBNAILS!=0 && thumb_mode && RESIDENT_THUMBNAILS==0)) begin
                menu_idle_count<=MENU_IDLE_START;
                if(DEMO_MENU!=0) begin
                    if(SEVEN_MENU==0) image_page<=0;
                    if(mode_long) begin
                        if(menu_level) menu_level<=0;else menu_open<=0;
                    end else begin menu_level<=1;menu_item<=0;end
                end else if(menu_level) menu_level<=0;
                else if(menu_group==3) menu_open<=0;
                else begin menu_level<=1;menu_item<=0;image_page<=0;end
            end

            // A held key cannot turn into an edit after a menu transition.
            if(clock_asleep || save_busy || !mode_n || !confirm_n || confirm_press || switch_changed || mode_short || mode_long ||
               (!plus_n && !minus_n)) begin
                blocked<=1;release_count<=0;
                plus_repeat<=0;minus_repeat<=0;
                plus_count<=REPEAT_START;minus_count<=REPEAT_START;
            end else if(blocked) begin
                if(plus_n && minus_n && mode_n && confirm_n) begin
                    if(release_count==7) blocked<=0;
                    else release_count<=release_count+1'b1;
                end else release_count<=0;
            end else if(ENABLE_THUMBNAILS!=0 && thumb_mode && !menu_open && (RESIDENT_THUMBNAILS==0 || thumb_keys)) begin
                plus_repeat<=0;minus_repeat<=0;plus_count<=REPEAT_START;minus_count<=REPEAT_START;
            end else if(!menu_open) begin
                if(ENABLE_PLAY_OPTIONS!=0 && main_keys_music) begin
                    track_next_event<=plus_short;track_prev_event<=minus_short;
                    if(plus_short || minus_short) audio_paused<=0;
                end else if(FULLSCREEN_THUMBNAILS==0 || !main_keys_thumbnail) begin next_event<=plus_short;prev_event<=minus_short;end
                plus_repeat<=0;minus_repeat<=0;
                plus_count<=REPEAT_START;minus_count<=REPEAT_START;
            end else if(!menu_level) begin
                plus_repeat<=0;minus_repeat<=0;
                plus_count<=REPEAT_START;minus_count<=REPEAT_START;
            end else begin
                if(plus_n || !edit_repeat) begin plus_repeat<=0;plus_count<=REPEAT_START;end
                else if(plus_long) begin plus_repeat<=1;plus_count<=REPEAT_START;end
                else if(plus_repeat) begin
                    if(plus_tick) plus_count<=REPEAT_START;
                    else plus_count<=plus_count_next;
                end
                if(minus_n || !edit_repeat) begin minus_repeat<=0;minus_count<=REPEAT_START;end
                else if(minus_long) begin minus_repeat<=1;minus_count<=REPEAT_START;end
                else if(minus_repeat) begin
                    if(minus_tick) minus_count<=REPEAT_START;
                    else minus_count<=minus_count_next;
                end
                if(plus_edit && !minus_edit) begin
                    if(auto_mode) begin auto_event<=1;auto_value<=1;end
                    else if(period_mode && period_sec<30) begin
                        period_sec<=period_sec+1'b1;period_change_valid<=1;
                    end else if(fade_mode && fade_level<3) fade_level<=fade_level+1'b1;
                    else if(source_mode) source_wav<=1;
                    else if(track_mode) begin
                        track_next_event<=plus_short;
                        if(plus_short) audio_paused<=0;
                    end
                    else if(play_mode && source_wav) begin
                        audio_paused<=0;
                        if(plus_short && playback_ended) replay_event<=1;
                    end
                    else if(volume_mode && volume<255) volume<=edit_result;
                    else if(save_mode) save_event<=plus_short;
                    else if(playback_mode_edit) playback_mode<=playback_mode==2 ? 2'd0 : playback_mode+1'b1;
                    else if(main_keys_edit) begin
                        if(FULLSCREEN_THUMBNAILS!=0) begin
                            if(main_keys_thumbnail) begin main_keys_thumbnail<=0;main_keys_music<=0;end
                            else if(main_keys_music) begin main_keys_music<=0;main_keys_thumbnail<=1;thumb_enter<=1;end
                            else main_keys_music<=1;
                        end else main_keys_music<=1;
                    end
                    else if(caption_edit && plus_short) caption_enabled<=1;
                    else if(diagonal_edit) diagonal_selected<=1;
                    else if(progress_edit) progress_visible<=1;
                    else if(binding_edit) audio_image_bind<=1;
                    else if(visual_edit) visual_enabled<=1;
                    else if(brightness_edit && brightness<255) brightness<=edit_result;
                    else if(contrast_edit && contrast<255) contrast<=edit_result;
                    else if(transparency_edit && menu_transparency<3) menu_transparency<=menu_transparency+1'b1;
                    else if(thumbnail_transparency_edit && thumbnail_transparency<3) thumbnail_transparency<=thumbnail_transparency+1'b1;
                    else if(picture_reset && plus_short) begin brightness<=255;contrast<=128;end
                    else if(ENABLE_SW4_THUMBNAILS==0 && ENABLE_THUMBNAILS!=0 && (SEVEN_MENU!=0 ? seven_group==3 && menu_item==0 : menu_group==0 && !image_page && menu_item==3) && plus_short) begin
                        thumb_enter<=1;if(RESIDENT_THUMBNAILS==0) begin menu_open<=0;menu_level<=0;end
                    end
                end else if(minus_edit && !plus_edit) begin
                    if(auto_mode) begin auto_event<=1;auto_value<=0;end
                    else if(period_mode && period_sec>1) begin
                        period_sec<=period_sec-1'b1;period_change_valid<=1;
                    end else if(fade_mode && fade_level>0) fade_level<=fade_level-1'b1;
                    else if(source_mode) source_wav<=0;
                    else if(track_mode) begin
                        track_prev_event<=minus_short;
                        if(minus_short) audio_paused<=0;
                    end
                    else if(play_mode && source_wav) audio_paused<=1;
                    else if(volume_mode && volume>0) volume<=edit_result;
                    else if(playback_mode_edit) playback_mode<=playback_mode==0 ? 2'd2 : playback_mode-1'b1;
                    else if(main_keys_edit) begin
                        if(FULLSCREEN_THUMBNAILS!=0) begin
                            if(main_keys_thumbnail) begin main_keys_thumbnail<=0;main_keys_music<=1;end
                            else if(main_keys_music) main_keys_music<=0;
                            else begin main_keys_thumbnail<=1;thumb_enter<=1;end
                        end else main_keys_music<=0;
                    end
                    else if(caption_edit && minus_short) caption_enabled<=0;
                    else if(diagonal_edit) diagonal_selected<=0;
                    else if(progress_edit) progress_visible<=0;
                    else if(binding_edit) audio_image_bind<=0;
                    else if(visual_edit) visual_enabled<=0;
                    else if(brightness_edit && brightness>0) brightness<=edit_result;
                    else if(contrast_edit && contrast>0) contrast<=edit_result;
                    else if(transparency_edit && menu_transparency>0) menu_transparency<=menu_transparency-1'b1;
                    else if(thumbnail_transparency_edit && thumbnail_transparency>0) thumbnail_transparency<=thumbnail_transparency-1'b1;
                    else if(ENABLE_SW4_THUMBNAILS==0 && RESIDENT_THUMBNAILS!=0 && ENABLE_THUMBNAILS!=0 && (SEVEN_MENU!=0 ? seven_group==3 && menu_item==0 : menu_group==0 && !image_page && menu_item==3) && minus_short)
                        thumb_enter<=0;
                end
            end

            // Context-sensitive KEY1 on the main screen; menu confirmation stays separate.
            if(!clock_asleep && confirm_action && !menu_open && !main_keys_thumbnail &&
                    !(ENABLE_THUMBNAILS!=0 && thumb_mode && RESIDENT_THUMBNAILS==0)) begin
                if(ENABLE_PLAY_OPTIONS!=0 && main_keys_music) begin
                    if(ENABLE_PLAY_CONTROL!=0 && source_wav) begin
                        audio_paused<=!audio_paused;
                        if(playback_ended) begin audio_paused<=0;replay_event<=1;end
                    end
                end else begin auto_event<=1;auto_value<=!auto_play_enabled;end
            end
            if(!clock_asleep && confirm_action && menu_open && menu_level) begin
                if(save_mode) save_event<=1;
                else if(picture_reset) begin brightness<=255;contrast<=128;end
                else if(play_mode && source_wav) begin
                    audio_paused<=!audio_paused;
                    if(playback_ended) begin audio_paused<=0;replay_event<=1;end
                end else if(ENABLE_SW4_THUMBNAILS==0 && ENABLE_THUMBNAILS!=0 && (SEVEN_MENU!=0 ? seven_group==3 && menu_item==0 : menu_group==0 && !image_page && menu_item==3)) begin
                    thumb_enter<=1;
                    if(RESIDENT_THUMBNAILS==0) begin menu_open<=0;menu_level<=0;end
                end
            end
            if(!menu_open || save_busy || !plus_n || !minus_n || !mode_n || !confirm_n || confirm_press ||
               plus_short || minus_short || mode_short || mode_long ||
               plus_long || minus_long) menu_idle_count<=MENU_IDLE_START;
            else if(menu_idle_done) begin
                menu_open<=0;menu_level<=0;menu_idle_count<=MENU_IDLE_START;
                blocked<=1;release_count<=0;
            end else menu_idle_count<=menu_idle_next;
            // SW4 controls visibility only; the menu selects the key target.
            if(ENABLE_SW4_THUMBNAILS!=0) begin
                thumb_enter<=main_sw_valid && main_sw_stable[2];
            end
        end
    end
endmodule

`timescale 1ns/1ps
// Clock and timer control. BCD byte operations share one dual-port ROM.
// Seconds retain the exact divider boundary. Carry propagation is private;
// consumers take frame snapshots only while time_stable is asserted.
module clock_timer_control #(
    parameter integer CLOCK_HZ=25000000,
    parameter integer ENABLE_SHARED_LABEL_ROM=0,
    parameter integer ENABLE_LOW_POWER_MENU=0
)(
    input wire clk,rst,
    input wire [2:0] command,
    input wire [1:0] selection,
    output reg [23:0] time_bcd,
    output reg time_valid,timer_enabled,sleeping,
    output reg clock_display_enabled,
    output reg [15:0] timer_bcd,edit_bcd,
    output reg edit_minutes,
    output wire time_stable,
    output wire [1:0] edit_owner,
    input wire label_request,
    input wire [8:0] label_address,
    output wire label_grant,
    output reg label_response_valid,
    output wire [6:0] label_glyph
);
    localparam integer DIV_WIDTH=CLOCK_HZ<2 ? 1 : $clog2(CLOCK_HZ);
    localparam [DIV_WIDTH-1:0] DIV_START=CLOCK_HZ==25000000 ? 1 : 0;
    reg [DIV_WIDTH-1:0] second_divider;
    wire divider_done=CLOCK_HZ==25000000 ? second_divider==25'h0d40870 : second_divider==CLOCK_HZ-1;
    wire [DIV_WIDTH-1:0] divider_next;
    generate if(CLOCK_HZ==25000000) begin : g_shift_second
        assign divider_next={second_divider[0]^second_divider[3],second_divider[24:1]};
    end else begin : g_binary_second
        assign divider_next=second_divider+1'b1;
    end endgenerate
    reg command_seen;
    reg [1:0] selection_q;
    reg [2:0] phase;
    reg minute_roll,edit_pending,edit_target_minutes;
    assign time_stable=phase==0 || phase==5;
    assign edit_owner=selection_q;
    wire command_event=command_seen!=command[2];
    wire [6:0] time_operand=phase==1 ? time_bcd[14:8] : phase==3 ? time_bcd[22:16] : time_bcd[6:0];
    wire [8:0] time_address={1'b0,phase==3,time_operand};
    wire [6:0] edit_operand=edit_minutes ? edit_bcd[6:0] : edit_bcd[14:8];
    wire [8:0] edit_address={command[0],!edit_minutes,edit_operand};
    wire edit_request=time_stable && command_event && !sleeping && selection!=0 &&
        selection==selection_q && !command[1] && (ENABLE_LOW_POWER_MENU==0 || selection!=3);
    localparam integer LABEL_ROM_DEPTH=ENABLE_SHARED_LABEL_ROM!=0 ? 1024 : 512;
    // This optional table is bound to the full seven-category production menu.
    localparam ENABLE_SW4_THUMBNAILS=1,ENABLE_CAPTION=1,ENABLE_CLOCK_TIMER=1;
    function [48:0] seven_category;
        input [2:0] category;
        begin case(category)
            0:seven_category={7'd1,7'd2,7'd14,7'd23,21'd0};
            1:seven_category={7'd5,7'd121,7'd14,7'd23,21'd0};
            2:seven_category={7'd65,7'd66,35'd0};
            3:seven_category=ENABLE_SW4_THUMBNAILS!=0 ? 49'd0 : {7'd104,7'd105,7'd1,28'd0};
            4:seven_category={7'd5,7'd6,7'd67,7'd72,7'd76,14'd0};
            5:seven_category={7'd77,7'd20,7'd73,7'd74,21'd0};
            6:seven_category={7'd7,7'd8,7'd3,7'd4,21'd0};
            7:seven_category=ENABLE_LOW_POWER_MENU!=0 ? {7'd81,7'd43,7'd120,28'd0} : 49'd0;
            default:seven_category=49'd0;
        endcase end
    endfunction
    function [48:0] seven_item;
        input [2:0] category,entry;
        begin
            seven_item=49'd0;
            case(category)
                0:case(entry)
                    0:seven_item=ENABLE_LOW_POWER_MENU!=0 ? {7'd5,7'd119,7'd80,7'd12,21'd0} : {7'd5,7'd119,7'd80,7'd81,21'd0};
                    1:seven_item={7'd11,7'd12,7'd13,7'd14,21'd0};
                    2:seven_item={7'd13,7'd14,7'd15,7'd16,21'd0};
                endcase
                1:case(entry)
                    0:seven_item={7'd14,7'd23,7'd5,7'd24,21'd0};
                    1:seven_item={7'd25,7'd26,7'd27,7'd28,21'd0};
                    2:seven_item={7'd14,7'd23,7'd125,7'd97,21'd0};
                    3:seven_item={7'd14,7'd23,7'd82,7'd83,21'd0};
                endcase
                2:case(entry)
                    0:seven_item={7'd65,7'd66,7'd102,7'd103,21'd0};
                    1:seven_item={7'd69,7'd70,7'd19,7'd20,21'd0};
                endcase
                3:case(entry)
                    0:seven_item={7'd104,7'd105,7'd1,7'd106,7'd107,14'd0};
                    1:seven_item={7'd116,7'd117,7'd97,28'd0};
                endcase
                4:case(entry)
                    0:seven_item={7'd5,7'd6,7'd94,7'd95,21'd0};
                endcase
                5:case(entry)
                    0:seven_item={7'd96,7'd97,35'd0};
                    1:seven_item={7'd98,7'd99,7'd97,28'd0};
                    2:seven_item={7'd5,7'd29,35'd0};
                    3:seven_item={7'd100,7'd101,7'd122,7'd41,21'd0};
                    4:if(ENABLE_CAPTION!=0) seven_item={7'd1,7'd1,7'd1,7'd1,21'd0};
                endcase
                6:case(entry)
                    0:seven_item={7'd68,7'd93,7'd43,7'd123,21'd0};
                    1:seven_item={7'd115,7'd86,7'd116,7'd117,21'd0};
                    2:seven_item={7'd32,7'd33,7'd3,7'd4,21'd0};
                    3:if(ENABLE_CLOCK_TIMER!=0 && ENABLE_LOW_POWER_MENU==0) seven_item={7'd46,7'd47,7'd3,7'd4,21'd0};
                    4:if(ENABLE_CLOCK_TIMER!=0 && ENABLE_LOW_POWER_MENU==0) seven_item={7'd108,7'd46,7'd3,7'd4,21'd0};
                endcase
                7:if(ENABLE_LOW_POWER_MENU!=0) case(entry)
                    0:seven_item={7'd46,7'd47,7'd3,7'd4,21'd0};
                    1:seven_item={7'd108,7'd46,7'd46,7'd47,21'd0};
                    2:seven_item={7'd36,7'd37,7'd108,7'd46,21'd0};
                    3:seven_item={7'd46,7'd47,7'd94,7'd95,21'd0};
                endcase
            endcase
        end
    endfunction
    function [6:0] char_at;
        input [48:0] word;
        input [2:0] index;
        begin case(index)
            0:char_at=word[48:42];1:char_at=word[41:35];
            2:char_at=word[34:28];3:char_at=word[27:21];
            4:char_at=word[20:14];5:char_at=word[13:7];
            6:char_at=word[6:0];default:char_at=0;
        endcase end
    endfunction
    (* rom_style="bram" *) reg [7:0] bcd_steps [0:LABEL_ROM_DEPTH-1];
    reg [7:0] time_result,edit_result;
    wire [9:0] port_b_address=ENABLE_SHARED_LABEL_ROM!=0 && !edit_request ?
        {1'b1,label_address} : {1'b0,edit_address};
    assign label_grant=ENABLE_SHARED_LABEL_ROM!=0 && !rst && label_request && !edit_request;
    assign label_glyph=edit_result[6:0];
    always @(posedge clk or posedge rst) begin
        if(rst) label_response_valid<=0;
        else label_response_valid<=label_grant;
    end
    integer index,value,limit,result;
    initial begin
        for(index=0;index<LABEL_ROM_DEPTH;index=index+1) begin
            if(index<512) begin
            value=index&127;limit=(index&128)!=0 ? 8'h23 : 8'h59;
            if((index&256)!=0)
                result=value==0 ? limit : (value&15)==0 ? value-7 : value-1;
            else
                result=value==limit ? 0 : (value&15)==9 ? value+7 : value+1;
            bcd_steps[index]=result;
            end else if(index<576) bcd_steps[index]={1'b0,char_at(seven_category((index-512)>>3),index&7)};
            else if(index<896) bcd_steps[index]={1'b0,char_at(seven_item(((index-576)>>3)/5,((index-576)>>3)%5),index&7)};
            else bcd_steps[index]=0;
        end
    end
    always @(posedge clk) begin
        if(phase==1 || phase==3 || phase==5) time_result<=bcd_steps[{1'b0,time_address}];
        if(edit_request || label_grant) edit_result<=bcd_steps[port_b_address];
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            second_divider<=DIV_START;time_bcd<=0;time_valid<=0;
            timer_enabled<=0;timer_bcd<=0;sleeping<=0;clock_display_enabled<=1;
            edit_bcd<=0;edit_minutes<=0;command_seen<=0;selection_q<=0;
            phase<=5;minute_roll<=0;edit_pending<=0;edit_target_minutes<=0;
        end else begin
            edit_pending<=edit_request;
            if(edit_request) edit_target_minutes<=edit_minutes;
            case(phase)
                1:phase<=2;
                2:begin
                    time_bcd[15:8]<=time_result;
                    phase<=time_bcd[15:8]==8'h59 ? 3 : 5;
                end
                3:phase<=4;
                4:begin time_bcd[23:16]<=time_result;phase<=5;end
                5:begin
                    phase<=0;minute_roll<=0;
                    if(minute_roll && timer_enabled && time_bcd[23:8]==timer_bcd) begin
                        sleeping<=1;timer_enabled<=0;
                    end
                end
            endcase
            if(time_valid) begin
                if(divider_done) begin
                    second_divider<=DIV_START;time_bcd[7:0]<=time_result;
                    minute_roll<=time_bcd[7:0]==8'h59;
                    phase<=time_bcd[7:0]==8'h59 ? 1 : 5;
                end else second_divider<=divider_next;
            end
            // Physical keys are separated by milliseconds; defer their toggle
            // consumption for the at-most-four carry clocks, without losing it.
            if(time_stable) begin
                command_seen<=command[2];selection_q<=selection;
                if(selection!=selection_q) begin
                    edit_bcd<=selection==1 ? time_bcd[23:8] : timer_bcd;
                    edit_minutes<=0;edit_pending<=0;
                end else if(command_event) begin
                    if(sleeping) begin
                        if(command[1:0]==2) sleeping<=0;
                    end else if(ENABLE_LOW_POWER_MENU!=0 && selection==3 && command[1:0]!=3) begin
                        case(command[1:0])
                            0:clock_display_enabled<=1;
                            1:clock_display_enabled<=0;
                            2:clock_display_enabled<=!clock_display_enabled;
                        endcase
                    end else if(selection!=0) begin
                        case(command[1:0])
                            2:if(!edit_minutes) edit_minutes<=1;
                              else begin
                                  edit_minutes<=0;
                                  if(selection==1) begin
                                      time_bcd<={edit_bcd,8'd0};time_valid<=1;
                                      second_divider<=DIV_START;phase<=5;minute_roll<=0;
                                  end else if(time_valid) begin timer_bcd<=edit_bcd;timer_enabled<=1;end
                              end
                            3:if(selection==2 || ENABLE_LOW_POWER_MENU!=0 && selection==3) begin timer_enabled<=0;edit_minutes<=0;end
                        endcase
                    end
                end
            end
            if(edit_pending && selection==selection_q && !sleeping) begin
                if(edit_target_minutes) edit_bcd[7:0]<=edit_result;
                else edit_bcd[15:8]<=edit_result;
            end
        end
    end
endmodule
