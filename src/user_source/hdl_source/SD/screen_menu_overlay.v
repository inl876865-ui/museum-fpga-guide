`timescale 1ns/1ps

// Three-column HDMI menu: category, setting, current value. The current
// settings need only two navigation levels; the value column is not a
// separate editor. All inputs are latched together at a frame boundary.
module screen_menu_overlay #(parameter integer ENABLE_PLAY_CONTROL=0,
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
    input wire clk,rst_n,frame_start,
    input wire de,
    input wire [9:0] pixel_x,
    input wire [11:0] pixel_y,
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
    output reg [23:0] rgb_out,
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
    output wire [6:0] caption_font_address,
    input wire [7:0] caption_font_byte,
    input wire [1:0] clock_edit_owner,
    input wire [23:0] clock_time,
    input wire clock_valid,clock_timer_enabled,clock_edit_minutes,
    input wire clock_display_enabled,
    input wire [15:0] clock_timer,clock_edit,
    input wire label_grant,label_response_valid,
    input wire [6:0] label_glyph,
    output wire label_request,
    output wire [8:0] label_address
);
    reg open_q,level_q,auto_q,source_q,paused_q,ended_q,keys_music_q;
    reg [1:0] playback_q,transparency_q,thumbnail_transparency_q;
    reg keys_thumbnail_q;
    reg visual_q,image_page_q,thumbnail_view_q,thumbnail_waiting_q;
    reg [4:0] thumbnail_focus_q;
    reg [5:0] thumbnail_count_q;
    reg [3:0] thumbnail_ready_q,thumbnail_failed_q;
    reg [7:0] brightness_q,contrast_q;
    reg [1:0] group_q,fade_q,save_q;
    localparam integer SEVEN_MENU=(DEMO_MENU==2);
    localparam integer LOW_POWER_MENU=ENABLE_LOW_POWER_MENU!=0 && ENABLE_CLOCK_TIMER!=0 && SEVEN_MENU!=0 && ENABLE_SW4_THUMBNAILS!=0;
    wire [2:0] seven_group={image_page_q,group_q};
    reg [MENU_ITEM_BITS-1:0] item_q;reg bind_q;
    reg progress_q,diagonal_q;
    reg caption_q;
    reg clock_display_q;
    wire six_rows=ENABLE_DIAGONAL_TRANSITION!=0 && group_q==0;
    wire five_rows=ENABLE_AUDIO_IMAGE_BIND!=0 && group_q==0 || ENABLE_AUDIO_PROGRESS!=0 && group_q==3;
    reg [5:0] period_q;
    reg [7:0] volume_q;
    reg [3:0] track_q,count_q;
    reg open_delay_q;
    assign menu_visible=open_delay_q;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            open_q<=0;level_q<=0;group_q<=0;item_q<=0;visual_q<=1;bind_q<=0;progress_q<=1;diagonal_q<=0;
            caption_q<=1;clock_display_q<=1;
            image_page_q<=0;brightness_q<=255;contrast_q<=128;transparency_q<=2'd2;thumbnail_transparency_q<=2'd2;
            thumbnail_view_q<=0;thumbnail_waiting_q<=0;thumbnail_focus_q<=0;thumbnail_count_q<=0;
            thumbnail_ready_q<=0;thumbnail_failed_q<=0;
            auto_q<=0;source_q<=1;paused_q<=0;ended_q<=0;period_q<=3;fade_q<=1;
            volume_q<=128;track_q<=0;count_q<=0;save_q<=0;playback_q<=0;keys_music_q<=0;keys_thumbnail_q<=0;
        end else if(frame_start) begin
            open_q<=menu_open;level_q<=menu_level;
            visual_q<=ENABLE_AUDIO_VISUAL!=0 && visual_enabled;
            group_q<=menu_group;item_q<=menu_item;bind_q<=ENABLE_AUDIO_IMAGE_BIND!=0 && audio_image_bind;
            diagonal_q<=ENABLE_DIAGONAL_TRANSITION!=0 && diagonal_selected;
            progress_q<=ENABLE_AUDIO_PROGRESS!=0 && progress_visible;
            caption_q<=ENABLE_CAPTION!=0 && caption_enabled;
            clock_display_q<=LOW_POWER_MENU==0 || clock_display_enabled;
            image_page_q<=ENABLE_PICTURE_ADJUST!=0 && image_page;
            brightness_q<=brightness;contrast_q<=contrast;
            transparency_q<=ENABLE_MENU_TRANSPARENCY!=0 ? menu_transparency : 2'd0;
            thumbnail_transparency_q<=DEMO_MENU!=0 ? thumbnail_transparency : 2'd2;
            thumbnail_view_q<=ENABLE_THUMBNAILS!=0 && thumbnail_view;
            thumbnail_waiting_q<=thumbnail_waiting;thumbnail_focus_q<=thumbnail_focus;
            thumbnail_count_q<=thumbnail_count;thumbnail_ready_q<=thumbnail_ready;thumbnail_failed_q<=thumbnail_failed;
            auto_q<=auto_enabled;source_q<=source_wav;
            paused_q<=ENABLE_PLAY_CONTROL!=0 && audio_paused;
            ended_q<=ENABLE_PLAY_CONTROL!=0 && audio_ended;
            period_q<=period_sec;fade_q<=fade_level;
            volume_q<=volume;track_q<=track_number;
            count_q<=track_count;save_q<=save_status;
            playback_q<=ENABLE_PLAY_OPTIONS!=0 ? playback_mode : 2'd0;
            keys_music_q<=ENABLE_PLAY_OPTIONS!=0 && main_keys_music;
            keys_thumbnail_q<=FULLSCREEN_THUMBNAILS!=0 && main_keys_thumbnail;
        end
    end

    // One left-category and one right-item label are prefetched per line.
    // Restrict the optional ROM layout to its explicitly bound feature set.
    localparam integer SHARED_LABELS=ENABLE_SHARED_LABEL_ROM!=0 && SEVEN_MENU!=0 &&
        COMPACT_MENU!=0 && ENABLE_SW4_THUMBNAILS!=0 && ENABLE_CAPTION!=0 && ENABLE_CLOCK_TIMER!=0;
    (* ram_style="dram" *) reg [6:0] glyph_cache [0:15];
    reg shared_label_selected;
    generate if(SHARED_LABELS!=0) begin : g_shared_labels
function [5:0] item_word_index;
    input [2:0] cat,entry;
    reg valid_entry;
    begin
        case(cat)
            0:valid_entry=entry<3;
            1:valid_entry=entry<4;
            2,3:valid_entry=entry<2;
            4:valid_entry=entry==0;
            5,6:valid_entry=entry<5;
            default:valid_entry=LOW_POWER_MENU!=0 && entry<4;
        endcase
        item_word_index=valid_entry ? 6'd8+{cat,2'b00}+{3'd0,cat}+{3'd0,entry} :
            LOW_POWER_MENU!=0 ? 6'd63 : 6'd7;
    end
endfunction
        reg de_previous,prefetch_pending,filling,cache_ready;
        reg [3:0] fill_index,pending_index;
        wire [2:0] left_row=pixel_y<140 ? 0 : pixel_y<180 ? 1 : pixel_y<220 ? 2 :
            pixel_y<260 ? 4 : pixel_y<300 ? 5 : LOW_POWER_MENU!=0 && pixel_y<340 ? 7 : 6;
        wire [2:0] right_row=pixel_y<158 ? 0 : pixel_y<216 ? 1 : pixel_y<274 ? 2 : pixel_y<332 ? 3 : 4;
        wire [5:0] label_word=fill_index[3] ? item_word_index(seven_group,right_row) : {3'd0,left_row};
        assign label_address={label_word,fill_index[2:0]};
        assign label_request=filling && !de && !prefetch_pending && !frame_start;
        always @(posedge clk) begin
            if(rst_n && !de && !prefetch_pending && !frame_start && label_response_valid)
                glyph_cache[pending_index]<=label_glyph;
        end
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                de_previous<=0;prefetch_pending<=0;filling<=0;cache_ready<=0;
                fill_index<=0;pending_index<=0;
            end else begin
                de_previous<=de;
                prefetch_pending<=frame_start || (de_previous && !de);
                if(frame_start) begin filling<=0;cache_ready<=0;end
                else if(prefetch_pending && !de) begin
                    // The wrapper has advanced pixel_y; it and the frame category
                    // stay stable through this horizontal-blank preload.
                    fill_index<=0;filling<=1;cache_ready<=0;
                end else begin
                    if(label_grant) begin
                        pending_index<=fill_index;
                        if(fill_index==15) filling<=0;else fill_index<=fill_index+1'b1;
                    end
                    if(label_response_valid && pending_index==15) cache_ready<=1;
                end
            end
        end
    end else begin : g_unshared_labels
        assign label_address=0;assign label_request=0;
    end endgenerate

    // Exact quarter-weight blending; all intermediates remain ten bits.
    function [7:0] blend_menu_channel;
        input [7:0] backdrop,foreground;
        input [1:0] level;
        reg [8:0] base;
        reg [9:0] weighted;
        reg [7:0] extra;
        begin
            base={1'b0,backdrop}+{1'b0,foreground};
            extra=level[1] ? backdrop : foreground;
            weighted={1'b0,base}+{1'b0,extra,1'b0};
            if(level==0) blend_menu_channel=foreground;
            else if(level==2) blend_menu_channel=base[8:1];
            else blend_menu_channel=weighted[9:2];
        end
    endfunction
    // Codes are defined by screen_menu_font.v; each word has five glyphs.
    function [34:0] category_text;
        input [1:0] category;
        begin case(category)
            0:category_text={7'd1,7'd2,7'd3,7'd4,7'd0}; // 图片设置
            1:category_text={7'd5,7'd6,7'd3,7'd4,7'd0}; // 音频设置
            2:category_text={7'd7,7'd8,7'd3,7'd4,7'd0}; // 系统设置
            default:category_text={7'd9,7'd10,7'd0,7'd0,7'd0}; // 退出
        endcase end
    endfunction
    function [34:0] item_text;
        input [1:0] category,entry;
        begin
            item_text=0;
            case(category)
                0:if(ENABLE_PICTURE_ADJUST!=0 && image_page_q) begin
                    case(entry)
                        0:item_text={7'd96,7'd97,7'd30,7'd31,7'd0}; // 亮度大小
                        1:item_text={7'd98,7'd99,7'd103,7'd97,7'd0}; // 对比强度
                        2:item_text={7'd100,7'd101,7'd102,7'd1,7'd0}; // 恢复原图
                        3:if(ENABLE_MENU_TRANSPARENCY!=0)item_text={7'd115,7'd86,7'd116,7'd117,7'd0}; // 菜单透明
                    endcase
                end else case(entry)
                    0:item_text={7'd11,7'd12,7'd13,7'd14,7'd0}; // 自动轮播
                    1:item_text={7'd13,7'd14,7'd15,7'd16,7'd0}; // 轮播周期
                    2:item_text={7'd17,7'd18,7'd19,7'd20,7'd0}; // 淡变帧数
                    3:if(ENABLE_THUMBNAILS!=0)item_text={7'd104,7'd105,7'd106,7'd107,7'd0}; // 缩略浏览
                endcase
                1:case(entry)
                    0:item_text={7'd14,7'd23,7'd5,7'd24,7'd0}; // 播放音源
                    1:item_text={7'd25,7'd26,7'd27,7'd28,7'd0}; // 选择歌曲
                    2:item_text=ENABLE_PLAY_CONTROL!=0 ? {7'd14,7'd23,7'd76,7'd77,7'd0} : {7'd5,7'd29,7'd30,7'd31,7'd0};
                    3:if(ENABLE_PLAY_CONTROL!=0)item_text={7'd5,7'd29,7'd30,7'd31,7'd0}; // 音量大小
                endcase
                2:case(entry)
                    0:item_text={7'd32,7'd33,7'd3,7'd4,7'd0}; // 保存设置
                    1:if(ENABLE_PLAY_OPTIONS!=0)item_text={7'd14,7'd23,7'd82,7'd83,7'd0}; // 播放模式
                    2:if(ENABLE_PLAY_OPTIONS!=0)item_text={7'd91,7'd92,7'd68,7'd93,7'd0}; // 主界按键
                    3:if(ENABLE_AUDIO_VISUAL!=0)item_text={7'd5,7'd6,7'd94,7'd95,7'd0}; // 音频显示
                endcase
                default:item_text=0;
            endcase
        end
    endfunction
    function [11:0] bcd8;
        input [7:0] value;
        integer i;
        reg [11:0] bcd;
        begin
            bcd=0;
            for(i=7;i>=0;i=i-1) begin
                if(bcd[3:0]>=5) bcd[3:0]=bcd[3:0]+3;
                if(bcd[7:4]>=5) bcd[7:4]=bcd[7:4]+3;
                if(bcd[11:8]>=5) bcd[11:8]=bcd[11:8]+3;
                bcd={bcd[10:0],value[i]};
            end
            bcd8=bcd;
        end
    endfunction
    // Volume and picture brightness belong to different categories, so one
    // decimal converter serves both without changing visible values.
    // Only one numeric value is visible at a given pixel in the seven menu.
    // Select its unchanged frame-latched input before one decimal converter.
    wire [7:0] numeric_value=SEVEN_MENU!=0 ?
        (seven_group==0 ? {2'b00,period_q} : pixel_y<158 ? brightness_q : pixel_y<216 ? contrast_q : volume_q) :
        ENABLE_PICTURE_ADJUST!=0 && (DEMO_MENU!=0 ? group_q==1 : group_q==0) ? brightness_q : volume_q;
    wire [11:0] volume_bcd=bcd8(numeric_value);
    wire [11:0] brightness_bcd=volume_bcd;
    wire [11:0] contrast_bcd=SEVEN_MENU!=0 ? volume_bcd : bcd8(contrast_q);
    wire [11:0] period_bcd=SEVEN_MENU!=0 ? volume_bcd : bcd8({2'b00,period_q});

    // Seven categories share the existing 60-bit menu snapshot.
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
            7:seven_category=LOW_POWER_MENU!=0 ? {7'd81,7'd43,7'd120,28'd0} : 49'd0;
            default:seven_category=49'd0;
        endcase end
    endfunction
    function [2:0] seven_item_count;
        input [2:0] category;
        begin case(category)
            0:seven_item_count=3;
            1:seven_item_count=4;
            2:seven_item_count=2;
            3:seven_item_count=ENABLE_SW4_THUMBNAILS!=0 ? 0 : FIXED_OPAQUE_THUMBNAILS!=0 ? 1 : 2;
            4:seven_item_count=1;
            5:seven_item_count=ENABLE_CAPTION!=0 ? 5 : 4;
            6:seven_item_count=LOW_POWER_MENU!=0 ? 3 : ENABLE_CLOCK_TIMER!=0 ? 5 : 3;
            7:seven_item_count=LOW_POWER_MENU!=0 ? 4 : 0;
            default:seven_item_count=0;
        endcase end
    endfunction
    function [48:0] seven_item;
        input [2:0] category,entry;
        begin
            seven_item=49'd0;
            case(category)
                0:case(entry)
                    0:seven_item=LOW_POWER_MENU!=0 ? {7'd5,7'd119,7'd80,7'd12,21'd0} : {7'd5,7'd119,7'd80,7'd81,21'd0};
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
                    3:if(ENABLE_CLOCK_TIMER!=0 && LOW_POWER_MENU==0) seven_item={7'd46,7'd47,7'd3,7'd4,21'd0};
                    4:if(ENABLE_CLOCK_TIMER!=0 && LOW_POWER_MENU==0) seven_item={7'd108,7'd46,7'd3,7'd4,21'd0};
                endcase
                7:if(LOW_POWER_MENU!=0) case(entry)
                    0:seven_item={7'd46,7'd47,7'd3,7'd4,21'd0};
                    1:seven_item={7'd108,7'd46,7'd46,7'd47,21'd0};
                    2:seven_item={7'd36,7'd37,7'd108,7'd46,21'd0};
                    3:seven_item={7'd46,7'd47,7'd94,7'd95,21'd0};
                endcase
            endcase
        end
    endfunction
    wire clock_current_selected=open_q && level_q && seven_group==(LOW_POWER_MENU!=0 ? 7 : 6) && item_q==(LOW_POWER_MENU!=0 ? 0 : 3);
    wire clock_edit_matches=item_q==(LOW_POWER_MENU!=0 ? 0 : 3) ? clock_edit_owner==1 : clock_edit_owner==2;
    wire [15:0] clock_menu_value=level_q && text_row==item_q && (LOW_POWER_MENU!=0 ? item_q<2 : item_q>=3) && clock_edit_matches ? clock_edit :
        text_row==(LOW_POWER_MENU!=0 ? 0 : 3) ? clock_time[23:8] : clock_timer;
    wire clock_timer_selected=open_q && level_q && seven_group==(LOW_POWER_MENU!=0 ? 7 : 6) && item_q==(LOW_POWER_MENU!=0 ? 1 : 4);
    function [48:0] seven_value;
        input [2:0] category,entry;
        begin
            seven_value=49'd0;
            case(category)
                0:case(entry)
                    0:seven_value=bind_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0};
                    1:seven_value=auto_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0};
                    2:seven_value=bind_q ? {7'd124,7'd5,7'd6,28'd0} : {7'd50+period_bcd[7:4],7'd50+period_bcd[3:0],7'd48,28'd0};
                endcase
                1:case(entry)
                    0:seven_value=source_q ? {7'd27,7'd28,35'd0} : {7'd38,7'd39,35'd0};
                    1:seven_value=count_q==0 ? {7'd61,42'd0} : {7'd50+track_q,7'd60,7'd50+count_q,28'd0};
                    2:seven_value=progress_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0};
                    3:case(playback_q)
                        0:seven_value={7'd14,7'd84,7'd79,7'd85,21'd0};
                        1:seven_value={7'd86,7'd28,7'd87,7'd88,21'd0};
                        2:seven_value={7'd89,7'd90,7'd87,7'd88,21'd0};
                    endcase
                endcase
                2:case(entry)
                    0:seven_value=diagonal_q ? {7'd98,7'd126,35'd0} : {7'd17,7'd18,35'd0};
                    1:case(fade_q)
                        0:seven_value={7'd50,7'd19,35'd0};
                        1:seven_value={7'd54,7'd19,35'd0};
                        2:seven_value={7'd58,7'd19,35'd0};
                        3:seven_value={7'd51,7'd56,7'd19,28'd0};
                    endcase
                endcase
                3:case(entry)
                    0:seven_value=thumbnail_view_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0};
                    1:seven_value=percent_text(thumbnail_transparency_q);
                endcase
                4:case(entry)
                    0:seven_value=visual_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0};
                endcase
                5:case(entry)
                    0:seven_value={7'd50+brightness_bcd[11:8],7'd50+brightness_bcd[7:4],7'd50+brightness_bcd[3:0],28'd0};
                    1:seven_value={7'd50+contrast_bcd[11:8],7'd50+contrast_bcd[7:4],7'd50+contrast_bcd[3:0],28'd0};
                    2:seven_value={7'd50+volume_bcd[11:8],7'd50+volume_bcd[7:4],7'd50+volume_bcd[3:0],28'd0};
                    3:seven_value={7'd40,7'd41,35'd0};
                    4:if(ENABLE_CAPTION!=0) seven_value=caption_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0};
                endcase
                6:case(entry)
                    0:seven_value=keys_thumbnail_q ? {7'd104,7'd105,7'd1,28'd0} : keys_music_q ? {7'd5,7'd121,35'd0} : {7'd1,7'd2,35'd0};
                    1:seven_value=percent_text(transparency_q);
                    2:case(save_q)
                        0:seven_value={7'd40,7'd41,35'd0};
                        1:seven_value={7'd32,7'd33,7'd111,28'd0};
                        2:seven_value={7'd42,7'd43,35'd0};
                        3:seven_value={7'd44,7'd45,35'd0};
                    endcase
                    3:if(ENABLE_CLOCK_TIMER!=0 && LOW_POWER_MENU==0) seven_value=49'd0;
                    4:if(ENABLE_CLOCK_TIMER!=0 && LOW_POWER_MENU==0 && !clock_timer_enabled && !clock_timer_selected)
                        seven_value={7'd36,7'd37,35'd0};
                endcase
                7:if(LOW_POWER_MENU!=0) case(entry)
                    0:seven_value=0;
                    1:if(!clock_timer_enabled && !clock_timer_selected) seven_value={7'd36,7'd37,35'd0};
                    2:seven_value=clock_timer_enabled ? {7'd40,7'd41,35'd0} : {7'd36,7'd37,35'd0};
                    3:seven_value=clock_display_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0};
                endcase
            endcase
        end
    endfunction

    function [6:0] seven_value_glyph;
        input [2:0] category,entry;
        input [2:0] index;
        reg [11:0] selected_bcd;
        reg [3:0] selected_digit;
        reg digit_selected;
        begin
            selected_bcd=0;selected_digit=0;digit_selected=0;
            seven_value_glyph=0;
            case(category)
                0:case(entry)
                    0:seven_value_glyph=char_at(bind_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0},index);
                    1:seven_value_glyph=char_at(auto_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0},index);
                    2:begin
                        if(bind_q) seven_value_glyph=char_at({7'd124,7'd5,7'd6,28'd0},index);
                        else case(index)
                            0:begin selected_digit=period_bcd[7:4];digit_selected=1;end
                            1:begin selected_digit=period_bcd[3:0];digit_selected=1;end
                            2:seven_value_glyph=7'd48;
                        endcase
                    end
                endcase
                1:case(entry)
                    0:seven_value_glyph=char_at(source_q ? {7'd27,7'd28,35'd0} : {7'd38,7'd39,35'd0},index);
                    1:begin
                        if(count_q==0) seven_value_glyph=char_at({7'd61,42'd0},index);
                        else case(index)
                            0:begin selected_digit=track_q;digit_selected=1;end
                            1:seven_value_glyph=7'd60;
                            2:begin selected_digit=count_q;digit_selected=1;end
                        endcase
                    end
                    2:seven_value_glyph=char_at(progress_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0},index);
                    3:case(playback_q)
                        0:seven_value_glyph=char_at({7'd14,7'd84,7'd79,7'd85,21'd0},index);
                        1:seven_value_glyph=char_at({7'd86,7'd28,7'd87,7'd88,21'd0},index);
                        2:seven_value_glyph=char_at({7'd89,7'd90,7'd87,7'd88,21'd0},index);
                    endcase
                endcase
                2:case(entry)
                    0:seven_value_glyph=char_at(diagonal_q ? {7'd98,7'd126,35'd0} : {7'd17,7'd18,35'd0},index);
                    1:case(fade_q)
                        0:seven_value_glyph=char_at({7'd50,7'd19,35'd0},index);
                        1:seven_value_glyph=char_at({7'd54,7'd19,35'd0},index);
                        2:seven_value_glyph=char_at({7'd58,7'd19,35'd0},index);
                        3:seven_value_glyph=char_at({7'd51,7'd56,7'd19,28'd0},index);
                    endcase
                endcase
                3:case(entry)
                    0:seven_value_glyph=char_at(thumbnail_view_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0},index);
                    1:seven_value_glyph=char_at(percent_text(thumbnail_transparency_q),index);
                endcase
                4:case(entry)
                    0:seven_value_glyph=char_at(visual_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0},index);
                endcase
                5:case(entry)
                    0,1,2:begin
                        selected_bcd=entry==0 ? brightness_bcd : entry==1 ? contrast_bcd : volume_bcd;
                        case(index)
                            0:selected_digit=selected_bcd[11:8];
                            1:selected_digit=selected_bcd[7:4];
                            2:selected_digit=selected_bcd[3:0];
                        endcase
                        if(index<3) digit_selected=1;
                    end
                    3:seven_value_glyph=char_at({7'd40,7'd41,35'd0},index);
                    4:if(ENABLE_CAPTION!=0) seven_value_glyph=char_at(caption_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0},index);
                endcase
                6:case(entry)
                    0:seven_value_glyph=char_at(keys_thumbnail_q ? {7'd104,7'd105,7'd1,28'd0} : keys_music_q ? {7'd5,7'd121,35'd0} : {7'd1,7'd2,35'd0},index);
                    1:seven_value_glyph=char_at(percent_text(transparency_q),index);
                    2:case(save_q)
                        0:seven_value_glyph=char_at({7'd40,7'd41,35'd0},index);
                        1:seven_value_glyph=char_at({7'd32,7'd33,7'd111,28'd0},index);
                        2:seven_value_glyph=char_at({7'd42,7'd43,35'd0},index);
                        3:seven_value_glyph=char_at({7'd44,7'd45,35'd0},index);
                    endcase
                    3:if(ENABLE_CLOCK_TIMER!=0 && LOW_POWER_MENU==0) seven_value_glyph=char_at(49'd0,index);
                    4:if(ENABLE_CLOCK_TIMER!=0 && LOW_POWER_MENU==0 && !clock_timer_enabled && !clock_timer_selected)
                        seven_value_glyph=char_at({7'd36,7'd37,35'd0},index);
                endcase
                7:if(LOW_POWER_MENU!=0) case(entry)
                    0:seven_value_glyph=char_at(0,index);
                    1:if(!clock_timer_enabled && !clock_timer_selected) seven_value_glyph=char_at({7'd36,7'd37,35'd0},index);
                    2:seven_value_glyph=char_at(clock_timer_enabled ? {7'd40,7'd41,35'd0} : {7'd36,7'd37,35'd0},index);
                    3:seven_value_glyph=char_at(clock_display_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0},index);
                endcase
            endcase
            if(digit_selected) seven_value_glyph=7'd50+selected_digit;
        end
    endfunction
    // Length is determined by the same value controls, without inspecting
    // seven assembled character cells solely to right-align their start.
    function [2:0] seven_value_length;
        input [2:0] category,entry;
        begin
            seven_value_length=0;
            case(category)
                0:case(entry)
                    0,1:seven_value_length=2;
                    2:seven_value_length=3;
                endcase
                1:case(entry)
                    0,2:seven_value_length=2;
                    1:seven_value_length=count_q==0 ? 1 : 3;
                    3:seven_value_length=playback_q==3 ? 0 : 4;
                endcase
                2:case(entry)
                    0:seven_value_length=2;
                    1:seven_value_length=fade_q==3 ? 3 : 2;
                endcase
                3:case(entry)
                    0:seven_value_length=2;
                    1:seven_value_length=thumbnail_transparency_q==0 ? 2 : 3;
                endcase
                4:if(entry==0) seven_value_length=2;
                5:case(entry)
                    0,1,2:seven_value_length=3;
                    3:seven_value_length=2;
                    4:if(ENABLE_CAPTION!=0) seven_value_length=2;
                endcase
                6:case(entry)
                    0:seven_value_length=keys_thumbnail_q ? 3 : 2;
                    1:seven_value_length=transparency_q==0 ? 2 : 3;
                    2:seven_value_length=save_q==1 ? 3 : 2;
                    3:if(ENABLE_CLOCK_TIMER!=0 && LOW_POWER_MENU==0) seven_value_length=5;
                    4:if(ENABLE_CLOCK_TIMER!=0 && LOW_POWER_MENU==0) seven_value_length=clock_timer_enabled || clock_timer_selected ? 5 : 2;
                endcase
                7:if(LOW_POWER_MENU!=0) case(entry)
                    0:seven_value_length=5;
                    1:seven_value_length=clock_timer_enabled || clock_timer_selected ? 5 : 2;
                    2,3:seven_value_length=2;
                endcase
            endcase
        end
    endfunction
    function [9:0] seven_value_start;
        input [2:0] category,entry;
        begin case(seven_value_length(category,entry))
            1:seven_value_start=552;2:seven_value_start=528;3:seven_value_start=504;
            4:seven_value_start=480;5:seven_value_start=456;6:seven_value_start=432;
            default:seven_value_start=408;
        endcase end
    endfunction
    // Right alignment uses glyph CELLS, not varying ink bounding boxes.
    function [2:0] seven_word_length;
        input [48:0] text;
        begin
            if(text[6:0]!=0) seven_word_length=7;
            else if(text[13:7]!=0) seven_word_length=6;
            else if(text[20:14]!=0) seven_word_length=5;
            else if(text[27:21]!=0) seven_word_length=4;
            else if(text[34:28]!=0) seven_word_length=3;
            else if(text[41:35]!=0) seven_word_length=2;
            else if(text[48:42]!=0) seven_word_length=1;
            else seven_word_length=0;
        end
    endfunction
    function [9:0] seven_value_x;
        input [48:0] text;
        begin case(seven_word_length(text))
            1:seven_value_x=552;2:seven_value_x=528;3:seven_value_x=504;
            4:seven_value_x=480;5:seven_value_x=456;6:seven_value_x=432;
            default:seven_value_x=408;
        endcase end
    endfunction
    function [48:0] demo_category;
        input [1:0] category;
        begin case(category)
            0:demo_category={7'd1,7'd2,7'd14,7'd23,21'd0};
            1:demo_category={7'd119,7'd120,7'd73,7'd74,21'd0};
            2:demo_category={7'd5,7'd121,7'd14,7'd23,21'd0};
            3:demo_category={7'd7,7'd8,7'd3,7'd4,21'd0};
        endcase end
    endfunction
    function [48:0] demo_item;
        input [1:0] category;
        input [2:0] entry;
        begin
            demo_item=0;
            case(category)
                0:case(entry)
                    0:demo_item={7'd11,7'd12,7'd13,7'd14,21'd0};
                    1:demo_item={7'd13,7'd14,7'd15,7'd16,21'd0};
                    2:demo_item=ENABLE_DIAGONAL_TRANSITION!=0 ? {7'd69,7'd70,7'd19,7'd20,21'd0} : {7'd17,7'd18,7'd19,7'd20,21'd0};
                    3:demo_item={7'd104,7'd105,7'd106,7'd107,21'd0};
                    4:demo_item={7'd5,7'd6,7'd122,7'd123,21'd0};
                    5:demo_item={7'd69,7'd70,7'd82,7'd83,21'd0}; // 切换模式
                endcase
                1:case(entry)
                    0:demo_item={7'd96,7'd97,35'd0};
                    1:demo_item={7'd98,7'd99,7'd97,28'd0};
                    2:demo_item={7'd100,7'd101,7'd102,7'd1,21'd0};
                    3:demo_item={7'd5,7'd6,7'd94,7'd95,21'd0};
                endcase
                2:case(entry)
                    0:demo_item={7'd14,7'd23,7'd5,7'd24,21'd0};
                    1:demo_item={7'd25,7'd26,7'd27,7'd28,21'd0};
                    2:demo_item={7'd5,7'd29,7'd30,7'd31,21'd0};
                    3:demo_item={7'd14,7'd23,7'd82,7'd83,21'd0};
                endcase
                3:case(entry)
                    0:demo_item={7'd91,7'd92,7'd82,7'd83,21'd0};
                    1:demo_item={7'd115,7'd86,7'd116,7'd117,21'd0};
                    2:demo_item={7'd104,7'd105,7'd116,7'd117,21'd0};
                    3:demo_item=ENABLE_AUDIO_PROGRESS!=0 ? {7'd14,7'd23,7'd125,7'd97,21'd0} : {7'd32,7'd33,7'd3,7'd4,21'd0};
                    4:demo_item={7'd32,7'd33,7'd3,7'd4,21'd0};
                endcase
            endcase
        end
    endfunction
    function [48:0] percent_text;
        input [1:0] alpha;
        begin case(alpha)
            0:percent_text={7'd50,7'd118,35'd0};
            1:percent_text={7'd52,7'd55,7'd118,28'd0};
            2:percent_text={7'd55,7'd50,7'd118,28'd0};
            3:percent_text={7'd57,7'd55,7'd118,28'd0};
        endcase end
    endfunction
    function [48:0] demo_value;
        input [1:0] category;
        input [2:0] entry;
        begin
            demo_value=0;
            case(category)
                0:case(entry)
                    0:demo_value=auto_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0};
                    1:demo_value=bind_q ? {7'd124,7'd5,7'd6,28'd0} : {7'd50+period_bcd[7:4],7'd50+period_bcd[3:0],7'd48,28'd0};
                    2:case(fade_q)
                        0:demo_value={7'd50,7'd19,35'd0};
                        1:demo_value={7'd54,7'd19,35'd0};
                        2:demo_value={7'd58,7'd19,35'd0};
                        3:demo_value={7'd51,7'd56,7'd19,28'd0};
                    endcase
                    3:demo_value=thumbnail_view_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0};
                    4:demo_value=bind_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0};
                    5:demo_value=diagonal_q ? {7'd98,7'd126,35'd0} : {7'd17,7'd18,35'd0};
                endcase
                1:case(entry)
                    0:demo_value={7'd50+brightness_bcd[11:8],7'd50+brightness_bcd[7:4],7'd50+brightness_bcd[3:0],28'd0};
                    1:demo_value={7'd50+contrast_bcd[11:8],7'd50+contrast_bcd[7:4],7'd50+contrast_bcd[3:0],28'd0};
                    2:demo_value={7'd75,7'd51,7'd40,7'd41,21'd0};
                    3:demo_value=visual_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0};
                endcase
                2:case(entry)
                    0:demo_value=source_q ? {7'd27,7'd28,35'd0} : {7'd38,7'd39,35'd0};
                    1:demo_value=count_q==0 ? {7'd61,42'd0} : {7'd50+track_q,7'd60,7'd50+count_q,28'd0};
                    2:demo_value={7'd50+volume_bcd[11:8],7'd50+volume_bcd[7:4],7'd50+volume_bcd[3:0],28'd0};
                    3:case(playback_q)
                        0:demo_value={7'd14,7'd84,7'd79,7'd85,21'd0};
                        1:demo_value={7'd86,7'd28,7'd87,7'd88,21'd0};
                        2:demo_value={7'd89,7'd90,7'd87,7'd88,21'd0};
                    endcase
                endcase
                3:case(entry)
                    0:demo_value=keys_thumbnail_q ? {7'd104,7'd105,7'd1,28'd0} : keys_music_q ? {7'd5,7'd121,35'd0} : {7'd1,7'd2,35'd0};
                    1:demo_value=percent_text(transparency_q);
                    2:demo_value=percent_text(thumbnail_transparency_q);
                    3,4:if(ENABLE_AUDIO_PROGRESS!=0 && entry==3)
                        demo_value=progress_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0};
                    else case(save_q)
                        0:demo_value={7'd75,7'd51,7'd40,7'd41,21'd0};
                        1:demo_value={7'd46,7'd47,35'd0};
                        2:demo_value={7'd42,7'd43,35'd0};
                        3:demo_value={7'd44,7'd45,35'd0};
                    endcase
                endcase
            endcase
        end
    endfunction
    localparam integer DIRECTORY_SHIFT=FULLSCREEN_THUMBNAILS!=0 ? 56 : 0;
    wire [11:0] directory_y=pixel_y+DIRECTORY_SHIFT;
    wire [1:0] directory_entry=directory_y<152 ? 2'd0 : directory_y<240 ? 2'd1 : directory_y<328 ? 2'd2 : 2'd3;
    wire [11:0] directory_top=directory_entry==0 ? 12'd64-DIRECTORY_SHIFT : directory_entry==1 ? 12'd152-DIRECTORY_SHIFT :
        directory_entry==2 ? 12'd240-DIRECTORY_SHIFT : 12'd328-DIRECTORY_SHIFT;
    wire [11:0] focus_top=thumbnail_focus_q[1:0]==0 ? 12'd64-DIRECTORY_SHIFT : thumbnail_focus_q[1:0]==1 ? 12'd152-DIRECTORY_SHIFT :
        thumbnail_focus_q[1:0]==2 ? 12'd240-DIRECTORY_SHIFT : 12'd328-DIRECTORY_SHIFT;
    wire [1:0] browser_slot=DIRECTORY_LAYOUT!=0 ? (pixel_x<208 ? directory_entry : thumbnail_focus_q[1:0]) :
        {pixel_y>=240,pixel_x>=320};
    wire [4:0] browser_image={thumbnail_focus_q[4:2],browser_slot};
    wire [5:0] browser_number={1'b0,browser_image}+1'b1;
    wire [3:0] browser_tens=browser_number>=30 ? 4'd3 : browser_number>=20 ? 4'd2 :
        browser_number>=10 ? 4'd1 : 4'd0;
    wire [3:0] browser_ones=browser_number-(browser_tens*10);
    wire [11:0] browser_bcd={4'd0,browser_tens,browser_ones};
    wire [3:0] browser_pages=({1'b0,thumbnail_count_q}+3)>>2;
    wire [9:0] browser_left=DIRECTORY_LAYOUT!=0 ? (pixel_x<208 ? 10'd24 : 10'd264) :
        (browser_slot[0] ? 10'd352 : 10'd128);
    wire [11:0] browser_top=DIRECTORY_LAYOUT!=0 ? (pixel_x<208 ? directory_top : 12'd120) :
        (browser_slot[1] ? 12'd256 : 12'd96);
    wire [9:0] browser_width=DIRECTORY_LAYOUT!=0 ? (pixel_x<208 ? 10'd80 : 10'd320) : 10'd160;
    wire [11:0] browser_height=DIRECTORY_LAYOUT!=0 ? (pixel_x<208 ? 12'd60 : 12'd240) : 12'd120;
    wire directory_photo_y=(directory_y>=64 && directory_y<124) || (directory_y>=152 && directory_y<212) ||
        (directory_y>=240 && directory_y<300) || (directory_y>=328 && directory_y<388);
    wire directory_photo_left=pixel_x>=24 && pixel_x<104 && directory_photo_y;
    wire directory_photo_right=pixel_x>=264 && pixel_x<584 && pixel_y>=120 && pixel_y<360;
    wire directory_photo_edge_y=directory_y[11:1]==32 || directory_y[11:1]==61 ||
        directory_y[11:1]==76 || directory_y[11:1]==105 || directory_y[11:1]==120 ||
        directory_y[11:1]==149 || directory_y[11:1]==164 || directory_y[11:1]==193;
    wire browser_inside=DIRECTORY_LAYOUT!=0 ? directory_photo_left || directory_photo_right :
        pixel_x>=browser_left && pixel_x<browser_left+browser_width && pixel_y>=browser_top && pixel_y<browser_top+browser_height;
    wire browser_border=DIRECTORY_LAYOUT!=0 ?
        (directory_photo_left && (pixel_x<26 || pixel_x>=102 || directory_photo_edge_y)) ||
        (directory_photo_right && (pixel_x<266 || pixel_x>=582 || pixel_y<122 || pixel_y>=358)) :
        browser_inside && (pixel_x<browser_left+2 || pixel_x>=browser_left+browser_width-2 || pixel_y<browser_top+2 || pixel_y>=browser_top+browser_height-2);
    wire directory_caption_y=(pixel_y>=80 && pixel_y<96) || (pixel_y>=168 && pixel_y<184) ||
        (pixel_y>=256 && pixel_y<272) || (pixel_y>=344 && pixel_y<360);
    wire browser_available=browser_image<thumbnail_count_q && thumbnail_ready_q[browser_slot] && !thumbnail_failed_q[browser_slot];
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

    // Nearest mapping of a 24-pixel cell to the existing 16-pixel ROM.
    // A small case table avoids /3, multipliers and additional font memory.
    function [3:0] scale24;
        input [4:0] offset;
        begin case(offset)
            0,1:scale24=0;2:scale24=1;3,4:scale24=2;5:scale24=3;
            6,7:scale24=4;8:scale24=5;9,10:scale24=6;11:scale24=7;
            12,13:scale24=8;14:scale24=9;15,16:scale24=10;17:scale24=11;
            18,19:scale24=12;20:scale24=13;21,22:scale24=14;23:scale24=15;
            default:scale24=0;
        endcase end
    endfunction
    reg [48:0] text_value;
    reg [6:0] glyph;
    reg [3:0] glyph_y,glyph_x;
    reg [2:0] text_row,glyph_index;
    reg [1:0] text_column;
    reg [2:0] text_type;
    reg [7:0] text_dx;
    reg [4:0] glyph_dx;
    reg in_text,double_size,selected_row,selected_edge;
    reg in_outer,in_inner,in_halo,in_separator,in_keybox;
    reg [9:0] text_x;
    reg [11:0] text_y;
    reg selected_y_area,selected_y_edge;
    wire [15:0] font_pixels,menu_font_pixels;
    reg [23:0] rgb_base,rgb_base_q,text_color,text_color_q;
    // The foreground is selected before exact combinational alpha blending.
    reg [23:0] blend_foreground;
    wire [23:0] dsp_blended_rgb;
    generate if(ENABLE_MENU_TRANSPARENCY!=0) begin:g_dsp_alpha
        dsp_alpha_channel red(.back(rgb_in[23:16]),.front(blend_foreground[23:16]),.level(transparency_q),.result(dsp_blended_rgb[23:16]));
        dsp_alpha_channel green(.back(rgb_in[15:8]),.front(blend_foreground[15:8]),.level(transparency_q),.result(dsp_blended_rgb[15:8]));
        dsp_alpha_channel blue(.back(rgb_in[7:0]),.front(blend_foreground[7:0]),.level(transparency_q),.result(dsp_blended_rgb[7:0]));
    end else begin:g_no_dsp_alpha
        assign dsp_blended_rgb=24'd0;
    end endgenerate

    reg [3:0] glyph_x_q;
    reg text_enable_q;
    screen_menu_font_rom #(.SEVEN_MENU(SEVEN_MENU),.ENABLE_CLOCK_TIMER(ENABLE_CLOCK_TIMER),.ENABLE_LOW_POWER_MENU(LOW_POWER_MENU)) u_font (.clk(clk),.glyph(glyph),.row(glyph_y),.pixels(menu_font_pixels));
    assign caption_font_address=ENABLE_SHARED_SCALING_RAM!=0 ? {glyph_index[1:0],glyph_y[3:0],glyph_x[3]} : 7'd0;
    generate if(ENABLE_CAPTION!=0) begin : g_caption_label
        wire [15:0] caption_font_pixels;
        wire [15:0] caption_legacy_pixels;
        wire label_selected=SEVEN_MENU!=0 && open_q && seven_group==5 &&
            text_row==4 && text_type==0 && in_text && glyph_index<4;
        reg label_selected_q;
        caption_label_font u_caption_label_font (.clk(clk),.glyph(glyph_index[1:0]),
            .row(glyph_y),.pixels(caption_legacy_pixels));
        assign caption_font_pixels=ENABLE_SHARED_SCALING_RAM!=0 ?
            {caption_font_byte,caption_font_byte} : caption_legacy_pixels;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) label_selected_q<=0;
            else label_selected_q<=label_selected;
        end
        assign font_pixels=label_selected_q ? caption_font_pixels : menu_font_pixels;
    end else begin : g_no_caption_label
        assign font_pixels=menu_font_pixels;
    end endgenerate
    // BRAM data and all pixel attributes describe the same input pixel.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rgb_base_q<=0;text_color_q<=0;glyph_x_q<=0;
            text_enable_q<=0;open_delay_q<=0;
        end else begin
            rgb_base_q<=rgb_base;text_color_q<=text_color;glyph_x_q<=glyph_x;
            text_enable_q<=(open_q || thumbnail_view_q) && de && in_outer && in_text && glyph!=0;
            open_delay_q<=open_q || thumbnail_view_q;
        end
    end
    always @* rgb_out=text_enable_q && font_pixels[15-glyph_x_q] ?
                     text_color_q : rgb_base_q;
    always @* begin
        text_value=0;glyph=0;glyph_y=0;glyph_x=0;
        text_row=0;glyph_index=0;text_column=0;text_type=0;shared_label_selected=0;
        text_x=0;text_y=0;selected_y_area=0;selected_y_edge=0;text_dx=0;glyph_dx=0;
        in_text=0;double_size=0;selected_row=0;selected_edge=0;
        in_outer=0;in_inner=0;in_halo=0;in_separator=0;in_keybox=0;
        if(COMPACT_MENU==0) begin
        if(pixel_y>=40 && pixel_y<72 && pixel_x>=256 && pixel_x<384) begin
            in_text=1;double_size=1;text_type=1;
            text_x=256;text_y=40;
            text_value=ENABLE_PICTURE_ADJUST!=0 && group_q==0 && image_page_q ?
                {7'd96,7'd97,7'd98,7'd99,21'd0} : {7'd14,7'd23,7'd3,7'd4,21'd0};
        end else if(pixel_y>=86 && pixel_y<102) begin
            in_text=1;text_type=2;text_y=86;
            if(pixel_x>=52 && pixel_x<84) begin
                text_x=52;text_value={7'd62,7'd63,35'd0}; // 分类
            end else if(pixel_x>=246 && pixel_x<(ENABLE_PICTURE_ADJUST!=0 && group_q==0 ? 326 : 278)) begin
                text_x=246;text_value=ENABLE_PICTURE_ADJUST!=0 && group_q==0 ?
                    {7'd25,7'd64,7'd51+image_page_q,7'd60,7'd52,14'd0} :
                    {7'd25,7'd64,35'd0}; // 选项 1/2
            end else if(pixel_x>=468 && pixel_x<500) begin
                text_x=468;text_value={7'd65,7'd66,35'd0}; // 当前
            end else in_text=0;
        end else if(pixel_y>=412 && pixel_y<428) begin
            in_text=1;text_type=3;text_y=412;
            if(pixel_x>=42 && pixel_x<154) begin
                text_x=42;
                text_value={7'd75,7'd54,7'd67,7'd68,7'd69,7'd70,7'd0};
            end else if(pixel_x>=222 && pixel_x<334) begin
                text_x=222;
                text_value=level_q ?
                    {7'd75,7'd54,7'd71,7'd68,7'd21,7'd22,7'd0} :
                    group_q==3 ?
                    {7'd75,7'd54,7'd71,7'd68,7'd9,7'd10,7'd0} :
                    {7'd75,7'd54,7'd71,7'd68,7'd72,7'd47,7'd0};
            end else if(pixel_x>=442 && pixel_x<554) begin
                text_x=442;
                text_value=ENABLE_PLAY_CONTROL!=0 && level_q && group_q==1 && item_q==2 ?
                    {7'd75,7'd52,7'd14,7'd75,7'd53,7'd79,7'd0} :
                    {7'd75,7'd52,7'd60,7'd75,7'd53,7'd73,7'd74};
            end else in_text=0;
        end else if(pixel_y>=126 && pixel_y<158) begin
            in_text=1;double_size=1;text_y=126;text_row=0;
        end else if(pixel_y>=192 && pixel_y<224) begin
            in_text=1;double_size=1;text_y=192;text_row=1;
        end else if(pixel_y>=258 && pixel_y<290) begin
            in_text=1;double_size=1;text_y=258;text_row=2;
        end else if(pixel_y>=324 && pixel_y<356) begin
            in_text=1;double_size=1;text_y=324;text_row=3;
        end
        end
        // Compact geometry replaces only text positioning; all labels, values
        // and frame snapshots below remain shared with the accepted menu.
        if(COMPACT_MENU!=0) begin
            in_text=0;double_size=0;text_type=0;text_value=0;
            if(pixel_y>=89 && pixel_y<113 && pixel_x>=105 && pixel_x<201) begin
                in_text=1;double_size=1;text_type=1;text_x=105;text_y=89;
                text_value={7'd14,7'd23,7'd3,7'd4,21'd0};
            end else if(pixel_y>=96 && pixel_y<112 && pixel_x>=440 && pixel_x<552) begin
                in_text=1;text_type=4;text_x=440;text_y=96;
                text_value=group_q==0 && ENABLE_PICTURE_ADJUST!=0 ?
                    {7'd1,7'd2,7'd51+image_page_q,7'd60,7'd52,14'd0} :
                    {category_text(group_q),14'd0};
            end else if(pixel_y>=142 && pixel_y<158) begin
                in_text=1;text_type=2;text_y=142;
                if(pixel_x>=91 && pixel_x<123) begin
                    text_x=91;text_value={7'd62,7'd63,35'd0};
                end else if(pixel_x>=250 && pixel_x<282) begin
                    text_x=250;text_value={7'd25,7'd64,35'd0};
                end else if(pixel_x>=450 && pixel_x<482) begin
                    text_x=450;text_value={7'd65,7'd66,35'd0};
                end else in_text=0;
            end else if(pixel_y>=382 && pixel_y<398) begin
                in_text=1;text_type=3;text_y=382;
                if(pixel_x>=91 && pixel_x<203) begin
                    text_x=91;text_value={7'd75,7'd54,7'd67,7'd68,7'd69,7'd70,7'd0};
                end else if(pixel_x>=239 && pixel_x<351) begin
                    text_x=239;text_value=level_q ?
                        {7'd75,7'd54,7'd71,7'd68,7'd21,7'd22,7'd0} : group_q==3 ?
                        {7'd75,7'd54,7'd71,7'd68,7'd9,7'd10,7'd0} :
                        {7'd75,7'd54,7'd71,7'd68,7'd72,7'd47,7'd0};
                end else if(pixel_x>=431 && pixel_x<543) begin
                    text_x=431;text_value=ENABLE_PLAY_CONTROL!=0 && level_q && group_q==1 && item_q==2 ?
                        {7'd75,7'd52,7'd14,7'd75,7'd53,7'd79,7'd0} :
                        {7'd75,7'd52,7'd60,7'd75,7'd53,7'd73,7'd74};
                end else in_text=0;
            end else if(pixel_y>=180 && pixel_y<204) begin
                in_text=1;double_size=1;text_y=180;text_row=0;
            end else if(pixel_y>=225 && pixel_y<249) begin
                in_text=1;double_size=1;text_y=225;text_row=1;
            end else if(pixel_y>=270 && pixel_y<294) begin
                in_text=1;double_size=1;text_y=270;text_row=2;
            end else if(pixel_y>=315 && pixel_y<339) begin
                in_text=1;double_size=1;text_y=315;text_row=3;
            end
        end
        if(in_text && text_type==0) begin
            if(pixel_x>=(COMPACT_MENU!=0 ? 99 : 50) && pixel_x<(COMPACT_MENU!=0 ? 195 : 178)) begin
                text_column=0;text_x=COMPACT_MENU!=0 ? 99 : 50;
                text_value={category_text(text_row[1:0]),14'd0};
            end else if(pixel_x>=(COMPACT_MENU!=0 ? 250 : 242) && pixel_x<(COMPACT_MENU!=0 ? 346 : 370)) begin
                text_column=1;text_x=COMPACT_MENU!=0 ? 250 : 242;
                text_value={item_text(group_q,text_row[1:0]),14'd0};
            end else if(pixel_x>=(COMPACT_MENU!=0 ? 450 : 464) && pixel_x<(COMPACT_MENU!=0 ? 546 : 592)) begin
                text_column=2;text_x=COMPACT_MENU!=0 ? 450 : 464;
                case(group_q)
                    0:if(ENABLE_PICTURE_ADJUST!=0 && image_page_q) begin
                        case(text_row)
                            0:text_value={7'd50+brightness_bcd[11:8],7'd50+brightness_bcd[7:4],7'd50+brightness_bcd[3:0],28'd0};
                            1:text_value={7'd50+contrast_bcd[11:8],7'd50+contrast_bcd[7:4],7'd50+contrast_bcd[3:0],28'd0};
                            2:text_value={7'd75,7'd52,7'd76,7'd77,21'd0}; // K2控制
                            3:if(ENABLE_MENU_TRANSPARENCY!=0)case(transparency_q)
                                0:text_value={7'd50,7'd118,35'd0};
                                1:text_value={7'd52,7'd55,7'd118,28'd0};
                                2:text_value={7'd55,7'd50,7'd118,28'd0};
                                3:text_value={7'd57,7'd55,7'd118,28'd0};
                            endcase
                        endcase
                    end else case(text_row)
                        0:text_value=auto_q ? {7'd34,7'd35,35'd0} :
                                              {7'd36,7'd37,35'd0};
                        1:text_value={7'd50+period_bcd[7:4],
                                      7'd50+period_bcd[3:0],7'd48,28'd0};
                        2:case(fade_q)
                            0:text_value={7'd50,7'd19,35'd0};
                            1:text_value={7'd54,7'd19,35'd0};
                            2:text_value={7'd58,7'd19,35'd0};
                            3:text_value={7'd51,7'd56,7'd19,28'd0};
                        endcase
                        3:if(ENABLE_THUMBNAILS!=0)text_value=RESIDENT_THUMBNAILS!=0 ?
                            (thumbnail_view_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0}) : {7'd75,7'd52,7'd76,7'd77,21'd0};
                    endcase
                    1:case(text_row)
                        0:text_value=source_q ? {7'd27,7'd28,35'd0} :
                                                {7'd38,7'd39,35'd0};
                        1:text_value=count_q==0 ? {7'd61,42'd0} :
                          {7'd50+track_q,7'd60,7'd50+count_q,28'd0};
                        2:if(ENABLE_PLAY_CONTROL!=0)
                            text_value=!source_q ? {7'd61,42'd0} :
                                ended_q ? {7'd80,7'd81,35'd0} :
                                paused_q ? {7'd78,7'd79,35'd0} : {7'd14,7'd23,35'd0};
                          else text_value={7'd50+volume_bcd[11:8],
                                      7'd50+volume_bcd[7:4],
                                      7'd50+volume_bcd[3:0],28'd0};
                        3:if(ENABLE_PLAY_CONTROL!=0)text_value={7'd50+volume_bcd[11:8],
                            7'd50+volume_bcd[7:4],7'd50+volume_bcd[3:0],28'd0};
                    endcase
                    2:if(text_row==1 && ENABLE_PLAY_OPTIONS!=0) begin
                        case(playback_q)
                            1:text_value={7'd86,7'd28,7'd87,7'd88,21'd0};
                            2:text_value={7'd89,7'd90,7'd87,7'd88,21'd0};
                            default:text_value={7'd14,7'd84,7'd79,7'd85,21'd0};
                        endcase
                    end else if(text_row==2 && ENABLE_PLAY_OPTIONS!=0)
                        text_value=keys_thumbnail_q ? {7'd104,7'd105,7'd1,28'd0} :
                            keys_music_q ? {7'd69,7'd27,7'd28,28'd0} :
                            {7'd69,7'd1,7'd2,28'd0};
                    else if(text_row==3 && ENABLE_AUDIO_VISUAL!=0)
                        text_value=visual_q ? {7'd34,7'd35,35'd0} : {7'd36,7'd37,35'd0};
                    else if(text_row==0)case(save_q)
                        0:text_value={7'd40,7'd41,35'd0};
                        1:text_value={7'd46,7'd47,35'd0};
                        2:text_value={7'd42,7'd43,35'd0};
                        3:text_value={7'd44,7'd45,35'd0};
                    endcase
                    default:text_value=0;
                endcase
            end else in_text=0;
        end
        if(thumbnail_view_q && !open_q && DIRECTORY_LAYOUT==0) begin
            in_text=0;double_size=0;text_type=5;text_value=0;
            if(pixel_y>=32 && pixel_y<56 && pixel_x>=272 && pixel_x<368) begin
                in_text=1;double_size=1;text_type=1;text_x=272;text_y=32;
                text_value={7'd1,7'd2,7'd106,7'd107,21'd0};
            end else if(pixel_y>=40 && pixel_y<56 && pixel_x>=464 && pixel_x<544) begin
                in_text=1;text_type=4;text_x=464;text_y=40;
                text_value={7'd50+thumbnail_focus_q[4:2]+7'd1,7'd60,7'd50+browser_pages,7'd108,21'd0};
            end else if(pixel_y>=436 && pixel_y<452) begin
                in_text=1;text_type=3;text_y=436;
                if(pixel_x>=72 && pixel_x<184) begin
                    text_x=72;text_value={7'd75,7'd52,7'd60,7'd75,7'd53,7'd25,7'd26};
                end else if(pixel_x>=256 && pixel_x<368) begin
                    text_x=256;text_value={7'd75,7'd54,7'd40,7'd41,21'd0};
                end else if(pixel_x>=432 && pixel_x<544) begin
                    text_x=432;text_value={7'd75,7'd54,7'd71,7'd68,7'd21,7'd22,7'd0};
                end else in_text=0;
            end else if(browser_image<thumbnail_count_q &&
                        pixel_y>=browser_top+124 && pixel_y<browser_top+140 &&
                        pixel_x>=browser_left+64 && pixel_x<browser_left+96) begin
                in_text=1;text_x=browser_left+64;text_y=browser_top+124;
                text_value={7'd50+browser_bcd[7:4],7'd50+browser_bcd[3:0],35'd0};
            end else if(browser_image<thumbnail_count_q && browser_inside &&
                        (!browser_available || thumbnail_waiting_q && browser_image==thumbnail_focus_q) &&
                        pixel_y>=browser_top+52 && pixel_y<browser_top+68 &&
                        pixel_x>=browser_left+56 && pixel_x<browser_left+104) begin
                in_text=1;text_x=browser_left+56;text_y=browser_top+52;
                text_value=thumbnail_failed_q[browser_slot] ? {7'd44,7'd45,35'd0} :
                    {7'd109,7'd110,7'd111,28'd0};
            end
        end
        if(thumbnail_view_q && !open_q && DIRECTORY_LAYOUT!=0 && FULLSCREEN_THUMBNAILS==0) begin
            in_text=0;double_size=0;text_type=5;text_value=0;
            if(pixel_y>=24 && pixel_y<48 && pixel_x>=24 && pixel_x<120) begin
                in_text=1;double_size=1;text_type=1;text_x=24;text_y=24;
                text_value={7'd1,7'd2,7'd112,7'd113,21'd0};
            end else if(pixel_y>=32 && pixel_y<48 && pixel_x>=144 && pixel_x<208) begin
                in_text=1;text_type=4;text_x=144;text_y=32;
                text_value={7'd50+thumbnail_focus_q[4:2]+7'd1,7'd60,7'd50+browser_pages,7'd108,21'd0};
            end else if(pixel_y>=64 && pixel_y<88 && pixel_x>=400 && pixel_x<448) begin
                in_text=1;double_size=1;text_type=1;text_x=400;text_y=64;
                text_value=RESIDENT_THUMBNAILS!=0 ? {7'd1,7'd2,35'd0} : {7'd114,7'd107,35'd0};
            end else if(pixel_y>=440 && pixel_y<456) begin
                in_text=1;text_type=3;text_y=440;
                if(pixel_x>=24 && pixel_x<136) begin
                    text_x=24;text_value={7'd75,7'd52,7'd60,7'd75,7'd53,7'd25,7'd26};
                end else if(pixel_x>=272 && pixel_x<384) begin
                    text_x=272;text_value=RESIDENT_THUMBNAILS!=0 ? {7'd75,7'd54,7'd3,7'd4,21'd0} : {7'd75,7'd54,7'd40,7'd41,21'd0};
                end else if(RESIDENT_THUMBNAILS==0 && pixel_x>=448 && pixel_x<560) begin
                    text_x=448;text_value={7'd75,7'd54,7'd71,7'd68,7'd21,7'd22,7'd0};
                end else in_text=0;
            end else if(pixel_x>=120 && pixel_x<184 && directory_caption_y && browser_image<thumbnail_count_q) begin
                in_text=1;text_x=120;text_y=directory_top+16;
                text_value={7'd1,7'd2,7'd50+browser_bcd[7:4],7'd50+browser_bcd[3:0],21'd0};
            end else if(pixel_x>=392 && pixel_x<456 && pixel_y>=384 && pixel_y<400) begin
                in_text=1;text_x=392;text_y=384;
                text_value={7'd1,7'd2,7'd50+browser_bcd[7:4],7'd50+browser_bcd[3:0],21'd0};
            end else if(browser_inside && browser_image<thumbnail_count_q &&
                        (!browser_available || thumbnail_waiting_q && pixel_x>=208) &&
                        pixel_y>=browser_top+(browser_height-16)/2 && pixel_y<browser_top+(browser_height-16)/2+16 &&
                        pixel_x>=browser_left+(browser_width-48)/2 && pixel_x<browser_left+(browser_width-48)/2+48) begin
                in_text=1;text_x=browser_left+(browser_width-48)/2;text_y=browser_top+(browser_height-16)/2;
                text_value=thumbnail_failed_q[browser_slot] ? {7'd44,7'd45,35'd0} :
                    {7'd109,7'd110,7'd111,28'd0};
            end
        end
        if(FULLSCREEN_THUMBNAILS!=0 && thumbnail_view_q && !open_q) begin
            // Only a small number inside each card and a quiet page counter.
            in_text=0;double_size=0;text_type=6;text_value=0;
            if(browser_image<thumbnail_count_q && directory_photo_left &&
               pixel_x>=28 && pixel_x<60 && pixel_y>=directory_top+40 && pixel_y<directory_top+56) begin
                in_text=1;text_x=28;text_y=directory_top+40;
                text_value={7'd50+browser_tens,7'd50+browser_ones,35'd0};
            end else if(pixel_x>=24 && pixel_x<72 && pixel_y>=340 && pixel_y<356) begin
                in_text=1;text_type=4;text_x=24;text_y=340;
                text_value={7'd50+thumbnail_focus_q[4:2]+7'd1,7'd60,7'd50+browser_pages,28'd0};
            end
        end
        if(DEMO_MENU!=0 && open_q) begin
            in_text=0;double_size=0;text_type=0;text_value=0;
            if(pixel_y>=66 && pixel_y<90 && pixel_x>=54 && pixel_x<590) begin
                text_row=pixel_x<188 ? 0 : pixel_x<322 ? 1 : pixel_x<456 ? 2 : 3;
                text_x=text_row==0 ? 72 : text_row==1 ? 206 : text_row==2 ? 340 : 474;
                text_y=66;text_value=demo_category(text_row[1:0]);
                in_text=pixel_x>=text_x && pixel_x<text_x+96;double_size=1;text_type=1;
            end else if(pixel_y>=120 && pixel_y<136) begin
                if(pixel_x>=58 && pixel_x<170) begin
                    in_text=1;text_x=58;text_y=120;text_type=4;
                    text_value=keys_thumbnail_q ? {7'd91,7'd92,7'd104,7'd105,7'd1,14'd0} :
                        keys_music_q ? {7'd91,7'd92,7'd5,7'd121,21'd0} : {7'd91,7'd92,7'd1,7'd2,21'd0};
                end else if(pixel_x>=440 && pixel_x<552) begin
                    in_text=1;text_x=440;text_y=120;text_type=4;
                    text_value=keys_thumbnail_q ? {7'd75,7'd51,7'd40,7'd41,21'd0} : keys_music_q ?
                        {7'd75,7'd51,7'd14,7'd23,7'd78,7'd79,7'd0} : {7'd75,7'd51,7'd11,7'd12,7'd69,7'd70,7'd0};
                end
            end else if(pixel_y>=158 && pixel_y<(six_rows ? 357 : five_rows ? 346 : 335)) begin
                if(six_rows) begin
                    text_row=pixel_y<193 ? 0 : pixel_y<228 ? 1 : pixel_y<263 ? 2 : pixel_y<298 ? 3 : pixel_y<333 ? 4 : 5;
                    text_y=text_row==0 ? 158 : text_row==1 ? 193 : text_row==2 ? 228 :
                        text_row==3 ? 263 : text_row==4 ? 298 : 333;
                end else if(five_rows) begin
                    text_row=pixel_y<199 ? 0 : pixel_y<240 ? 1 : pixel_y<281 ? 2 : pixel_y<322 ? 3 : 4;
                    text_y=text_row==0 ? 158 : text_row==1 ? 199 : text_row==2 ? 240 : text_row==3 ? 281 : 322;
                end else begin
                    text_row=pixel_y<209 ? 0 : pixel_y<260 ? 1 : pixel_y<311 ? 2 : 3;
                    text_y=text_row==0 ? 158 : text_row==1 ? 209 : text_row==2 ? 260 : 311;
                end
                if(pixel_y<text_y+24) begin
                    if(pixel_x>=72 && pixel_x<168) begin
                        in_text=1;double_size=1;text_x=72;text_value=demo_item(group_q,text_row);
                    end else if(pixel_x>=462 && pixel_x<558) begin
                        in_text=1;double_size=1;text_x=462;text_value=demo_value(group_q,text_row);
                    end
                end
            end else if(pixel_y>=389 && pixel_y<405) begin
                text_y=389;text_type=3;
                if(pixel_x>=58 && pixel_x<170) begin
                    in_text=1;text_x=58;
                    text_value={7'd75,7'd51,7'd40,7'd41,21'd0};
                end else if(pixel_x>=232 && pixel_x<344) begin
                    in_text=1;text_x=232;
                    text_value=!level_q ? {7'd75,7'd54,7'd25,7'd26,21'd0} :
                        (group_q==0 && item_q==1 && bind_q) ? {7'd124,7'd5,7'd6,28'd0} :
                        (group_q==1 && item_q==2 || group_q==3 && item_q==(ENABLE_AUDIO_PROGRESS!=0 ? 4 : 3)) ?
                        {7'd75,7'd52,7'd40,7'd41,21'd0} : {7'd75,7'd52,7'd60,7'd75,7'd53,7'd73,7'd74};
                end else if(pixel_x>=440 && pixel_x<552) begin
                    in_text=1;text_x=440;
                    text_value=level_q ? {7'd75,7'd54,7'd25,7'd26,21'd0} : {7'd75,7'd54,7'd71,7'd68,7'd9,7'd10,7'd0};
                end
            end else if(pixel_y>=417 && pixel_y<433 && pixel_x>=440 && pixel_x<552) begin
                in_text=1;text_type=3;text_x=440;text_y=417;
                text_value=level_q ? {7'd75,7'd54,7'd71,7'd68,7'd21,7'd22,7'd0} : 49'd0;
            end
        end
        if(SEVEN_MENU!=0 && open_q) begin
            // One 24-pixel grid for every category, label, numeric and value word.
            in_text=0;double_size=0;text_column=0;text_row=0;text_type=0;text_value=0;
            if(pixel_y>=55 && pixel_y<79 && pixel_x>=60 && pixel_x<180) begin
                in_text=1;double_size=1;text_x=60;text_y=55;text_type=4;
                text_value={7'd14,7'd23,7'd127,7'd115,7'd86,14'd0};
            end else if(pixel_y>=63 && pixel_y<79 && pixel_x>=528 && pixel_x<576) begin
                in_text=1;text_x=528;text_y=63;text_type=4;text_value={7'd57,7'd62,7'd63,28'd0};
            end else if(pixel_x>=64 && pixel_x<208 && pixel_y>=100 && pixel_y<(ENABLE_SW4_THUMBNAILS!=0 && LOW_POWER_MENU==0 ? 340 : 380)) begin
                text_row=pixel_y<140 ? 0 : pixel_y<180 ? 1 : pixel_y<220 ? 2 :
                    pixel_y<260 ? 3 : pixel_y<300 ? 4 : pixel_y<340 ? 5 : 6;
                if(LOW_POWER_MENU!=0 && text_row==5) text_row=7;
                else if(LOW_POWER_MENU!=0 && text_row==6) text_row=6;
                else if(ENABLE_SW4_THUMBNAILS!=0 && text_row>=3) text_row=text_row+1'b1;
                text_y=text_row==0 ? 108 : text_row==1 ? 148 : text_row==2 ? 188 :
                    LOW_POWER_MENU!=0 ? (text_row==4 ? 228 : text_row==5 ? 268 : text_row==7 ? 308 : 348) :
                    ENABLE_SW4_THUMBNAILS!=0 ? (text_row==4 ? 228 : text_row==5 ? 268 : 308) : text_row==3 ? 228 : text_row==4 ? 268 : text_row==5 ? 308 : 348;
                if(pixel_y>=text_y && pixel_y<text_y+24) begin
                    in_text=1;double_size=1;text_x=64;text_type=1;shared_label_selected=SHARED_LABELS!=0;
                    text_value=SHARED_LABELS!=0 ? 49'd0 : seven_category(text_row);
                end
            end else if(pixel_x>=252 && pixel_x<576 && pixel_y>=100 &&
                pixel_y<((ENABLE_CAPTION!=0 && seven_group==5 || ENABLE_CLOCK_TIMER!=0 && LOW_POWER_MENU==0 && seven_group==6) ? 370 : 312)) begin
                text_row=pixel_y<158 ? 0 : pixel_y<216 ? 1 : pixel_y<274 ? 2 : pixel_y<332 ? 3 : 4;
                text_y=text_row==0 ? 108 : text_row==1 ? 166 : text_row==2 ? 224 : text_row==3 ? 282 : 340;
                if(text_row<seven_item_count(seven_group) && pixel_y>=text_y && pixel_y<text_y+24) begin
                    double_size=1;
                    if(pixel_x<396) begin in_text=1;text_x=252;text_type=0;shared_label_selected=SHARED_LABELS!=0;
                        text_value=SHARED_LABELS!=0 ? 49'd0 : seven_item(seven_group,text_row);end
                    else begin
                        text_value=LOW_POWER_MENU!=0 ? 49'd0 : seven_value(seven_group,text_row);text_x=seven_value_start(seven_group,text_row);text_type=2;
                        if(pixel_x>=text_x) in_text=1;
                    end
                end
            end else if(pixel_y>=410 && pixel_y<426) begin
                text_y=410;text_type=3;
                if(pixel_x>=58 && pixel_x<122) begin in_text=1;text_x=58;text_value={7'd75,7'd54,7'd25,7'd26,21'd0};end
                else if(pixel_x>=188 && pixel_x<252) begin in_text=1;text_x=188;
                    text_value={7'd75,7'd51,7'd40,7'd41,21'd0};end
                else if(pixel_x>=324 && pixel_x<436) begin in_text=1;text_x=324;text_value={7'd75,7'd52,7'd60,7'd75,7'd53,7'd73,7'd74};end
                else if(pixel_x>=488 && pixel_x<584) begin in_text=1;text_x=488;text_value={7'd71,7'd68,7'd75,7'd54,7'd21,7'd22,7'd0};end
            end
        end
        if(in_text) begin
            glyph_index=(pixel_x[6:0]-text_x[6:0]) >> (double_size ? 5 : 4);
            glyph_x=(pixel_x[4:0]-text_x[4:0]) >> (double_size ? 1 : 0);
            glyph_y=(pixel_y[4:0]-text_y[4:0]) >> (double_size ? 1 : 0);
            if(COMPACT_MENU!=0 && double_size) begin
                text_dx=pixel_x-text_x;
                if(text_dx<24) begin glyph_index=0;glyph_dx=text_dx;end
                else if(text_dx<48) begin glyph_index=1;glyph_dx=text_dx-24;end
                else if(text_dx<72) begin glyph_index=2;glyph_dx=text_dx-48;end
                else if(SEVEN_MENU==0 || text_dx<96) begin glyph_index=3;glyph_dx=text_dx-72;end
                else if(text_dx<120) begin glyph_index=4;glyph_dx=text_dx-96;end
                else if(text_dx<144) begin glyph_index=5;glyph_dx=text_dx-120;end
                else begin glyph_index=6;glyph_dx=text_dx-144;end
                glyph_x=scale24(glyph_dx);glyph_y=scale24(pixel_y-text_y);
            end
            glyph=shared_label_selected ? glyph_cache[{text_type==0,glyph_index}] : char_at(text_value,glyph_index);
            if(LOW_POWER_MENU!=0 && open_q && text_type==2)
                glyph=seven_value_glyph(seven_group,text_row,glyph_index);
            // Only the final two hint glyphs vary; keep the existing cells
            // and font/RGB pipeline instead of selecting whole label words.
            if(LOW_POWER_MENU!=0 && open_q && seven_group==7 && level_q && item_q<2 &&
               text_type==3 && text_x==188) begin
                case(glyph_index)
                    2:glyph=clock_edit_minutes ? 7'd32 : 7'd69;
                    3:glyph=clock_edit_minutes ? 7'd33 : 7'd70;
                endcase
            end
            if(ENABLE_CLOCK_TIMER!=0 && open_q && seven_group==(LOW_POWER_MENU!=0 ? 7 : 6) && text_type==2 &&
               (text_row==(LOW_POWER_MENU!=0 ? 0 : 3) || text_row==(LOW_POWER_MENU!=0 ? 1 : 4) && (clock_timer_enabled || clock_timer_selected))) begin
                case(glyph_index)
                    0:glyph=7'd50+clock_menu_value[15:12];
                    1:glyph=7'd50+clock_menu_value[11:8];
                    2:glyph=7'd49;
                    3:glyph=7'd50+clock_menu_value[7:4];
                    4:glyph=7'd50+clock_menu_value[3:0];
                    default:glyph=0;
                endcase
                if(!clock_valid && text_row==(LOW_POWER_MENU!=0 ? 0 : 3) && !clock_current_selected && glyph_index!=2 && glyph_index<5) glyph=7'd61;
            end
            // Browser strings are short and fixed. Select the final glyph
            // directly instead of multiplexing seven whole code words first.
            if(thumbnail_view_q && !open_q) begin
                case(text_type)
                    1:if(DIRECTORY_LAYOUT!=0 && text_x==400)
                        glyph=char_at(RESIDENT_THUMBNAILS!=0 ? {7'd1,7'd2,35'd0} : {7'd114,7'd107,35'd0},glyph_index);
                      else if(DIRECTORY_LAYOUT!=0)
                        glyph=char_at({7'd1,7'd2,7'd112,7'd113,21'd0},glyph_index);
                      else glyph=char_at({7'd1,7'd2,7'd106,7'd107,21'd0},glyph_index);
                    4:case(glyph_index)
                        0:glyph=7'd50+thumbnail_focus_q[4:2]+7'd1;
                        1:glyph=7'd60;2:glyph=7'd50+browser_pages;3:glyph=7'd108;
                        default:glyph=0;
                    endcase
                    3:if(text_x==(DIRECTORY_LAYOUT!=0 ? 24 : 72))
                        glyph=char_at({7'd75,7'd52,7'd60,7'd75,7'd53,7'd25,7'd26},glyph_index);
                      else if(text_x==(DIRECTORY_LAYOUT!=0 ? 272 : 256))
                        glyph=char_at(RESIDENT_THUMBNAILS!=0 ? {7'd75,7'd54,7'd3,7'd4,21'd0} : {7'd75,7'd54,7'd40,7'd41,21'd0},glyph_index);
                      else glyph=char_at({7'd75,7'd54,7'd71,7'd68,7'd21,7'd22,7'd0},glyph_index);
                    5:if(DIRECTORY_LAYOUT!=0 ? text_x==120 || text_y==384 : text_y==browser_top+124) begin
                        if(DIRECTORY_LAYOUT!=0) case(glyph_index)
                            0:glyph=1;1:glyph=2;2:glyph=7'd50+browser_tens;3:glyph=7'd50+browser_ones;
                            default:glyph=0;
                        endcase
                        else case(glyph_index)
                            0:glyph=7'd50+browser_tens;1:glyph=7'd50+browser_ones;default:glyph=0;
                        endcase
                      end else if(thumbnail_failed_q[browser_slot])
                        glyph=char_at({7'd44,7'd45,35'd0},glyph_index);
                      else glyph=char_at({7'd109,7'd110,7'd111,28'd0},glyph_index);
                    6:case(glyph_index)
                        0:glyph=7'd50+browser_tens;1:glyph=7'd50+browser_ones;
                        default:glyph=0;
                    endcase
                    default:glyph=0;
                endcase
            end
        end

        if(COMPACT_MENU==0) begin
        // Chamfered outer enclosure and two inner dividers.
        in_outer=pixel_x>=12'd16 && pixel_x<12'd624 && pixel_y>=12'd32 && pixel_y<12'd456 &&
            !(pixel_x<12'd40 && pixel_y<12'd56 && pixel_x+pixel_y<12'd72) &&
            !(pixel_x>=12'd600 && pixel_y<12'd56 && (12'd624-pixel_x)+pixel_y<12'd56) &&
            !(pixel_x<12'd40 && pixel_y>=12'd432 && pixel_x+(12'd456-pixel_y)<12'd40) &&
            !(pixel_x>=12'd600 && pixel_y>=12'd432 &&
              (12'd624-pixel_x)+(12'd456-pixel_y)<12'd24);
        in_inner=pixel_x>=12'd19 && pixel_x<12'd621 && pixel_y>=12'd35 && pixel_y<12'd453 &&
            !(pixel_x<12'd42 && pixel_y<12'd58 && pixel_x+pixel_y<12'd77) &&
            !(pixel_x>=12'd598 && pixel_y<12'd58 && (12'd621-pixel_x)+pixel_y<12'd58) &&
            !(pixel_x<12'd42 && pixel_y>=12'd430 && pixel_x+(12'd453-pixel_y)<12'd42) &&
            !(pixel_x>=12'd598 && pixel_y>=12'd430 &&
              (12'd621-pixel_x)+(12'd453-pixel_y)<12'd23);
        in_halo=pixel_x>=10 && pixel_x<630 && pixel_y>=28 && pixel_y<462;
        in_separator=in_outer &&
            (((pixel_x>=204 && pixel_x<207) ||
              (pixel_x>=426 && pixel_x<429)) && pixel_y>=80 && pixel_y<390 ||
             (pixel_y>=108 && pixel_y<110 && pixel_x>=30 && pixel_x<610) ||
             (pixel_y>=394 && pixel_y<396 && pixel_x>=30 && pixel_x<610));
        in_keybox=(pixel_y>=404 && pixel_y<435) &&
            ((pixel_x>=32 && pixel_x<186) ||
             (pixel_x>=212 && pixel_x<398) ||
             (pixel_x>=432 && pixel_x<608));
        case(pixel_x<204 ? group_q : item_q)
            2'd0:begin
                selected_y_area=pixel_y>=116 && pixel_y<166;
                selected_y_edge=pixel_y<118 || pixel_y>=164;
            end
            2'd1:begin
                selected_y_area=pixel_y>=182 && pixel_y<232;
                selected_y_edge=pixel_y<184 || pixel_y>=230;
            end
            2'd2:begin
                selected_y_area=pixel_y>=248 && pixel_y<298;
                selected_y_edge=pixel_y<250 || pixel_y>=296;
            end
            default:begin
                selected_y_area=pixel_y>=314 && pixel_y<364;
                selected_y_edge=pixel_y<316 || pixel_y>=362;
            end
        endcase
        selected_row=in_outer && selected_y_area &&
            ((pixel_x>=30 && pixel_x<196) ||
             (level_q && ((pixel_x>=216 && pixel_x<418) ||
                          (pixel_x>=438 && pixel_x<610))));
        selected_edge=selected_row &&
            (selected_y_edge ||
             (pixel_x<198 && (pixel_x<32 || pixel_x>=194)) ||
             (pixel_x>=216 && pixel_x<420 && (pixel_x<218 || pixel_x>=416)) ||
             (pixel_x>=438 && (pixel_x<440 || pixel_x>=608)));
        end
        if(COMPACT_MENU!=0) begin
            in_outer=pixel_x>=72 && pixel_x<568 && pixel_y>=72 && pixel_y<408;
            in_inner=pixel_x>=73 && pixel_x<567 && pixel_y>=73 && pixel_y<407;
            in_halo=0;in_keybox=0;
            in_separator=(pixel_y==129 || pixel_y==366) && pixel_x>=90 && pixel_x<550 ||
                pixel_x==224 && pixel_y>=129 && pixel_y<366;
            case(pixel_x<224 ? group_q : item_q)
                0:selected_y_area=pixel_y>=174 && pixel_y<210;
                1:selected_y_area=pixel_y>=219 && pixel_y<255;
                2:selected_y_area=pixel_y>=264 && pixel_y<300;
                3:selected_y_area=pixel_y>=309 && pixel_y<345;
            endcase
            selected_row=in_outer && selected_y_area &&
                ((pixel_x>=85 && pixel_x<212) || (level_q && pixel_x>=237 && pixel_x<554));
            selected_edge=selected_row && ((pixel_x>=85 && pixel_x<88) || (pixel_x>=237 && pixel_x<240));
        end
        rgb_base=rgb_in;text_color=24'hffffff;
        blend_foreground=24'd0;
        if(COMPACT_MENU==0 && open_q && de) begin
            if(in_halo && !in_outer) rgb_base=24'h0d492c;
            if(in_outer) begin
                rgb_base={4'd0,rgb_in[23:20],4'd0,rgb_in[15:12],
                         4'd0,rgb_in[7:4]} | 24'h0b1712;
                if(in_keybox) rgb_base=24'h10281d;
                if(selected_row) rgb_base=(level_q && pixel_x<204) ?
                                        24'h18392c : 24'h124333;
                if(in_separator) rgb_base=24'h228454;
                if(in_outer && !in_inner) rgb_base=24'h51ff91;
                if(selected_edge) rgb_base=(level_q && pixel_x<204) ?
                                         24'h2da968 : 24'h67ffb0;
                if(in_text && glyph!=0) begin
                    if(text_type==1) text_color=24'hb9ffcd;
                    else if(text_type==2) text_color=24'h52d889;
                    else if(text_type==3) text_color=24'h6edca1;
                    else text_color=selected_row ? 24'hffffff : 24'hd8f3e7;
                end
            end
        end
        if(COMPACT_MENU!=0 && open_q && de && in_outer) begin
            rgb_base=pixel_x<224 && pixel_y<367 ? 24'h1b222c : 24'h202733;
            if(selected_row) rgb_base=pixel_x<224 ? 24'h2b3644 : 24'h324b63;
            if(ENABLE_MENU_TRANSPARENCY!=0) begin
                    blend_foreground=rgb_base;
                    rgb_base=dsp_blended_rgb;
                end
            if(in_separator || !in_inner) rgb_base=24'h3b4655;
            if(selected_edge || (pixel_x>=91 && pixel_x<94 && pixel_y>=91 && pixel_y<114))
                rgb_base=24'h82bff2;
            text_color=24'heef3f8;
            if(text_type==2 || text_type==4) text_color=24'h9aaabb;
            else if(text_type==3) text_color=24'hbdcad7;
            else if(text_type==0 && text_column==0 && text_row[1:0]!=group_q)
                text_color=24'h9aaabb;
            else if(text_type==0 && text_column==2 && selected_row) text_color=24'h82bff2;
        end
        if(DEMO_MENU!=0 && open_q) begin
            in_outer=pixel_x>=40 && pixel_x<600 && pixel_y>=40 && pixel_y<440;
            in_inner=pixel_x>=41 && pixel_x<599 && pixel_y>=41 && pixel_y<439;
            in_halo=0;in_keybox=0;in_separator=0;
            selected_row=0;selected_edge=0;
            if(pixel_x>=54 && pixel_x<590 && pixel_y>=54 && pixel_y<104) begin
                selected_row=(group_q==0 && pixel_x<188) || (group_q==1 && pixel_x>=188 && pixel_x<322) ||
                    (group_q==2 && pixel_x>=322 && pixel_x<456) || (group_q==3 && pixel_x>=456);
                selected_edge=selected_row && pixel_y>=101;
            end else if(level_q && pixel_x>=55 && pixel_x<585) begin
                if(six_rows) begin
                    case(item_q)
                        0:begin selected_row=pixel_y>=152 && pixel_y<187;
                            selected_y_edge=pixel_y==152 || pixel_y==186;end
                        1:begin selected_row=pixel_y>=187 && pixel_y<222;
                            selected_y_edge=pixel_y==187 || pixel_y==221;end
                        2:begin selected_row=pixel_y>=222 && pixel_y<257;
                            selected_y_edge=pixel_y==222 || pixel_y==256;end
                        3:begin selected_row=pixel_y>=257 && pixel_y<292;
                            selected_y_edge=pixel_y==257 || pixel_y==291;end
                        4:begin selected_row=pixel_y>=292 && pixel_y<327;
                            selected_y_edge=pixel_y==292 || pixel_y==326;end
                        5:begin selected_row=pixel_y>=327 && pixel_y<362;
                            selected_y_edge=pixel_y==327 || pixel_y==361;end
                        6:begin selected_row=pixel_y>=362 && pixel_y<397;
                            selected_y_edge=pixel_y==362 || pixel_y==396;end
                        7:begin selected_row=pixel_y>=397 && pixel_y<432;
                            selected_y_edge=pixel_y==397 || pixel_y==431;end
                    endcase
                end else if(five_rows) begin
                    case(item_q)
                        0:selected_row=pixel_y>=152 && pixel_y<188;
                        1:selected_row=pixel_y>=193 && pixel_y<229;
                        2:selected_row=pixel_y>=234 && pixel_y<270;
                        3:selected_row=pixel_y>=275 && pixel_y<311;
                        4:selected_row=pixel_y>=316 && pixel_y<352;
                    endcase
                end else case(item_q)
                    0:selected_row=pixel_y>=152 && pixel_y<197;
                    1:selected_row=pixel_y>=203 && pixel_y<248;
                    2:selected_row=pixel_y>=254 && pixel_y<299;
                    3:selected_row=pixel_y>=305 && pixel_y<350;
                endcase
                selected_edge=selected_row && (pixel_x<59 || pixel_x>=583 ||
                    pixel_y==152 || pixel_y==196 || pixel_y==203 || pixel_y==247 ||
                    pixel_y==254 || pixel_y==298 || pixel_y==305 || pixel_y==349);
                if(six_rows) selected_edge=selected_row &&
                    (pixel_x<59 || pixel_x>=583 || selected_y_edge);
                else if(five_rows) selected_edge=selected_row &&
                    (pixel_x<59 || pixel_x>=583 || pixel_y==152 || pixel_y==187 || pixel_y==193 || pixel_y==228 ||
                     pixel_y==234 || pixel_y==269 || pixel_y==275 || pixel_y==310 || pixel_y==316 || pixel_y==351);
            end
            in_separator=pixel_x>=56 && pixel_x<584 && (pixel_y==110 || pixel_y==371);
            rgb_base=rgb_in;text_color=24'heef3f8;
            if(in_outer && de) begin
                rgb_base=selected_row ? 24'h324b63 : 24'h202733;
                if(ENABLE_MENU_TRANSPARENCY!=0) begin
                    blend_foreground=rgb_base;
                    rgb_base=dsp_blended_rgb;
                end
                if(in_separator || !in_inner) rgb_base=24'h3b4655;
                if(selected_edge) rgb_base=24'h82bff2;
                if(text_type==1) text_color=selected_row ? 24'h82bff2 : 24'hbdcad7;
                else if(text_type==3 || text_type==4) text_color=24'hbdcad7;
                else if(selected_row && text_x==462) text_color=24'h82bff2;
            end
        end
        if(SEVEN_MENU!=0 && open_q) begin
            in_outer=pixel_x>=40 && pixel_x<600 && pixel_y>=40 && pixel_y<440;
            in_inner=pixel_x>=41 && pixel_x<599 && pixel_y>=41 && pixel_y<439;
            in_halo=0;in_keybox=0;in_separator=0;selected_row=0;selected_edge=0;
            selected_y_edge=0;
            if(pixel_x>=52 && pixel_x<214 && pixel_y>=100 && pixel_y<378) begin
                if(ENABLE_SW4_THUMBNAILS!=0) begin
                    case(seven_group)
                        0:selected_row=pixel_y<138;1:selected_row=pixel_y>=140 && pixel_y<178;
                        2:selected_row=pixel_y>=180 && pixel_y<218;
                        4:selected_row=pixel_y>=220 && pixel_y<258;
                        5:selected_row=pixel_y>=260 && pixel_y<298;
                        6:selected_row=LOW_POWER_MENU!=0 ? pixel_y>=340 && pixel_y<378 : pixel_y>=300 && pixel_y<338;
                        7:if(LOW_POWER_MENU!=0) selected_row=pixel_y>=300 && pixel_y<338;
                    endcase
                end else
                case(seven_group)
                    0:selected_row=pixel_y<138;1:selected_row=pixel_y>=140 && pixel_y<178;
                    2:selected_row=pixel_y>=180 && pixel_y<218;3:selected_row=pixel_y>=220 && pixel_y<258;
                    4:selected_row=pixel_y>=260 && pixel_y<298;5:selected_row=pixel_y>=300 && pixel_y<338;
                    6:selected_row=pixel_y>=340;
                endcase
                selected_edge=selected_row && pixel_x<55;
            end else if(level_q && pixel_x>=244 && pixel_x<584) begin
                case(item_q)
                    0:begin selected_row=pixel_y>=100 && pixel_y<138;selected_y_edge=pixel_y==100 || pixel_y==137;end
                    1:begin selected_row=pixel_y>=158 && pixel_y<196;selected_y_edge=pixel_y==158 || pixel_y==195;end
                    2:begin selected_row=pixel_y>=216 && pixel_y<254;selected_y_edge=pixel_y==216 || pixel_y==253;end
                    3:begin selected_row=pixel_y>=274 && pixel_y<312;selected_y_edge=pixel_y==274 || pixel_y==311;end
                    4:if(ENABLE_CAPTION!=0 && seven_group==5 || ENABLE_CLOCK_TIMER!=0 && LOW_POWER_MENU==0 && seven_group==6) begin
                        selected_row=pixel_y>=332 && pixel_y<370;selected_y_edge=pixel_y==332 || pixel_y==369;
                    end
                endcase
                selected_edge=selected_row && (pixel_x<247 || pixel_x>=583 || selected_y_edge);
            end
            in_separator=(pixel_x>=40 && pixel_x<600 && (pixel_y==94 || pixel_y==395)) ||
                (pixel_x==225 && pixel_y>=95 && pixel_y<395);
            rgb_base=rgb_in;text_color=24'heef3f8;
            if(in_outer && de) begin
                rgb_base=selected_row ? 24'h324b63 : pixel_x<225 && pixel_y>=95 && pixel_y<395 ? 24'h1c2835 : 24'h202733;
                if(ENABLE_MENU_TRANSPARENCY!=0) begin
                    blend_foreground=rgb_base;
                    rgb_base=dsp_blended_rgb;
                end
                if(in_separator || !in_inner) rgb_base=24'h3b4655;
                if(selected_edge) rgb_base=24'h82bff2;
                if(text_type==1) text_color=text_row==seven_group ? 24'h82bff2 : 24'hbdcad7;
                else if(text_type==3 || text_type==4) text_color=24'hbdcad7;
                else if(text_type==2 && selected_row) text_color=24'h82bff2;
                if(ENABLE_CLOCK_TIMER!=0 && seven_group==(LOW_POWER_MENU!=0 ? 7 : 6) && level_q && text_type==2 &&
                   text_row==item_q && (LOW_POWER_MENU!=0 ? item_q<2 : item_q>=3)) begin
                    if(LOW_POWER_MENU!=0) begin
                        text_color=24'heef3f8;
                        if(clock_edit_matches && (clock_edit_minutes ? glyph_index>=3 && glyph_index<=4 : glyph_index<2))
                            text_color=24'h82bff2;
                    end else if(clock_edit_minutes ? glyph_index>=3 && glyph_index<=4 : glyph_index<2)
                        text_color=24'hffffff;
                end
            end
        end
        if(thumbnail_view_q && !open_q && FULLSCREEN_THUMBNAILS==0) begin
            in_outer=1;in_inner=1;
            rgb_base=de && browser_inside && browser_available ? rgb_in : 24'h1b222c;
            if(DIRECTORY_LAYOUT!=0) begin
                if(pixel_x<208 && !browser_inside) rgb_base=24'h202733;
                if(pixel_x==208) rgb_base=24'h3b4655;
                if(pixel_x>=12 && pixel_x<196 && pixel_y>=directory_top-8 && pixel_y<directory_top+68 &&
                   directory_entry==thumbnail_focus_q[1:0] && !browser_inside) rgb_base=24'h324b63;
                if(pixel_x>=12 && pixel_x<15 && pixel_y>=directory_top-8 && pixel_y<directory_top+68 &&
                   directory_entry==thumbnail_focus_q[1:0]) rgb_base=24'h82bff2;
            end
            text_color=24'heef3f8;
            if(text_type==3 || text_type==4) text_color=24'h9aaabb;
            if(de && browser_border) rgb_base=browser_image==thumbnail_focus_q ? 24'h82bff2 : 24'h3b4655;
            if(text_type==5 && browser_image==thumbnail_focus_q) text_color=24'h82bff2;
            if(text_type==5 && thumbnail_failed_q[browser_slot]) text_color=24'hff8f87;
        end
        if(FULLSCREEN_THUMBNAILS!=0 && thumbnail_view_q && !open_q) begin
            in_outer=1;in_inner=1;rgb_base=rgb_in;text_color=24'heef3f8;
            // The full-size picture stays untouched outside the floating cards.
            if(de && directory_photo_left && browser_image<thumbnail_count_q) begin
                if(pixel_x>=28 && pixel_x<60 && pixel_y>=directory_top+40 && pixel_y<directory_top+56)
                    rgb_base={1'b0,rgb_in[23:17],1'b0,rgb_in[15:9],1'b0,rgb_in[7:1]};
                if(pixel_x==24 || pixel_x==103 || pixel_y==directory_top || pixel_y==directory_top+59)
                    rgb_base=browser_image==thumbnail_focus_q ? 24'h82bff2 :
                        {1'b0,rgb_in[23:17],1'b0,rgb_in[15:9],1'b0,rgb_in[7:1]};
            end
            if(STRONG_THUMB_BORDER!=0 && de && thumbnail_focus_q<thumbnail_count_q) begin
                if(pixel_x>=24 && pixel_x<104 && pixel_y>=focus_top && pixel_y<focus_top+60 &&
                   (pixel_x<27 || pixel_x>=101 || pixel_y<focus_top+3 || pixel_y>=focus_top+57)) rgb_base=24'h82bff2;
                else if(pixel_x>=23 && pixel_x<105 && pixel_y>=focus_top-1 && pixel_y<focus_top+61 &&
                        (pixel_x==23 || pixel_x==104 || pixel_y==focus_top-1 || pixel_y==focus_top+60)) rgb_base=24'h0b111a;
            end
            if(text_type==4) text_color=24'hbdcad7;
        end
    end
endmodule
