`timescale 1ns/1ps
// Fits strictly in x580..635, to the right of the unchanged x64..575 visualizer.
module audio_progress_overlay #(parameter integer ENABLE_CLOCK_TIMER=0,
    parameter integer ENABLE_CLOCK_DISPLAY_CONTROL=0) (
    input wire clk,rst_n,frame_start,de,enable,menu_open,source_wav,valid,paused,ended,
    input wire [9:0] pixel_x,
    input wire [11:0] pixel_y,
    input wire [23:0] rgb_in,elapsed_bcd,total_bcd,
    input wire long_time,
    input wire [4:0] fill_pixels,
    output reg [23:0] rgb_out,
    input wire [23:0] clock_time,
    input wire clock_valid,
    input wire clock_display_enabled
);
    reg clock_visible_q;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) clock_visible_q<=0;
        else if(frame_start) clock_visible_q<=ENABLE_CLOCK_TIMER!=0 && !menu_open &&
            (ENABLE_CLOCK_DISPLAY_CONTROL==0 || clock_display_enabled);
    end
    reg visible_q,paused_q,ended_q,long_q;
    reg [23:0] elapsed_q,total_q;
    reg [4:0] fill_q;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin visible_q<=0;paused_q<=0;ended_q<=0;long_q<=0;elapsed_q<=0;total_q<=0;fill_q<=0;end
        else if(frame_start) begin
            visible_q<=enable && !menu_open && source_wav && valid;
            paused_q<=paused;ended_q<=ended;long_q<=long_time;
            elapsed_q<=elapsed_bcd;total_q<=total_bcd;fill_q<=fill_pixels>30 ? 30 : fill_pixels;
        end
    end
    function [4:0] inset;
        input [4:0] row;
        reg [3:0] r;
        begin
            r=row>15 ? 31-row : row;
            case(r)
                0:inset=12;1:inset=9;2:inset=7;3:inset=6;4:inset=5;
                5:inset=4;6:inset=3;7,8:inset=2;9,10:inset=1;default:inset=0;
            endcase
        end
    endfunction
    function [14:0] tiny_digit;
        input [3:0] code;
        begin case(code)
            0:tiny_digit=15'b111_101_101_101_111;
            1:tiny_digit=15'b010_110_010_010_111;
            2:tiny_digit=15'b111_001_111_100_111;
            3:tiny_digit=15'b111_001_111_001_111;
            4:tiny_digit=15'b101_101_111_001_001;
            5:tiny_digit=15'b111_100_111_001_111;
            6:tiny_digit=15'b111_100_111_101_111;
            7:tiny_digit=15'b111_001_010_010_010;
            8:tiny_digit=15'b111_101_111_101_111;
            9:tiny_digit=15'b111_101_111_001_111;
            10:tiny_digit=15'b000_010_000_010_000; // colon
            11:tiny_digit=15'b001_001_010_100_100; // slash
            12:tiny_digit=15'b000_000_111_000_000; // unset clock
            default:tiny_digit=0;
        endcase end
    endfunction
    function [3:0] time_char;
        input [23:0] value;
        input [3:0] column;
        input hours_mode;
        begin
            if(hours_mode) case(column)
                0:time_char=value[23:20];1:time_char=value[19:16];2,5:time_char=10;
                3:time_char=value[15:12];4:time_char=value[11:8];6:time_char=value[7:4];7:time_char=value[3:0];
                default:time_char=15;
            endcase else case(column)
                0:time_char=value[15:12];1:time_char=value[11:8];2:time_char=10;
                3:time_char=value[7:4];4:time_char=value[3:0];default:time_char=15;
            endcase
        end
    endfunction
    reg [5:0] x;
    reg [4:0] y,edge_inset;
    reg [3:0] column,code;
    reg [2:0] text_y,text_x;
    reg [14:0] dots;
    reg text_hit,icon_hit,panel_inside,border;
    wire left_panel=ENABLE_CLOCK_TIMER!=0 && pixel_x<60;
    reg [23:0] color;
    reg [8:0] red,green,blue;
    always @* begin
        rgb_out=rgb_in;x=0;y=0;edge_inset=0;column=0;code=15;text_y=0;text_x=0;dots=0;
        text_hit=0;icon_hit=0;panel_inside=0;border=0;color=24'hd5dbe2;red=0;green=0;blue=0;
        if(de && pixel_y>=416 && pixel_y<448 &&
           (clock_visible_q && pixel_x>=4 && pixel_x<60 || visible_q && pixel_x>=580 && pixel_x<636)) begin
            x=left_panel ? pixel_x-4 : pixel_x-580;y=pixel_y-416;edge_inset=inset(y);
            panel_inside=x>=edge_inset && x<56-edge_inset;
            border=panel_inside && (y==0 || y==31 || x==edge_inset || x==55-edge_inset);
            if(panel_inside) begin
                red={1'b0,rgb_in[23:16]}+9'h020;green={1'b0,rgb_in[15:8]}+9'h026;blue={1'b0,rgb_in[7:0]}+9'h02b;
                rgb_out={red[8:1],green[8:1],blue[8:1]};
                if(border) rgb_out=24'hbfc6ce;
                if(left_panel && x>=12 && x<44 && y>=13 && y<18) begin
                    column=(x-12)>>2;text_x=(x-12)&3;text_y=y-13;
                    code=clock_valid ? time_char(clock_time,column,1) : (column==2 || column==5 ? 10 : 12);
                end else if(!left_panel && !long_q && x>=6 && x<50 && y>=6 && y<11) begin
                    column=(x-6)>>2;text_x=(x-6)&3;text_y=y-6;
                    code=column<5 ? time_char(elapsed_q,column,0) : column==5 ? 11 : time_char(total_q,column-6,0);
                end else if(!left_panel && long_q && x>=12 && x<44 && (y>=4 && y<9 || y>=11 && y<16)) begin
                    column=(x-12)>>2;text_x=(x-12)&3;
                    text_y=y<9 ? y-4 : y-11;
                    code=time_char(y<9 ? elapsed_q : total_q,column,1);
                end
                dots=tiny_digit(code);
                text_hit=code!=15 && text_x<3 && dots[14-(text_y+text_y+text_y)-text_x];
                // The icon sits below the time, next to the thin horizontal progress line.
                if(!left_panel && x>=7 && x<13 && y>=21 && y<27) begin
                    if(ended_q) icon_hit=1;
                    else if(!paused_q) icon_hit=x<9 || x>=11;
                    else icon_hit=x-7<=(y<24 ? y-21 : 26-y)+1;
                end
                if(!left_panel && x>=20 && x<50 && y>=24 && y<26)
                    rgb_out=x-20<fill_q ? 24'h82a0b5 : 24'h49515c;
                if(text_hit || icon_hit) rgb_out=color;
            end
        end
    end
endmodule
