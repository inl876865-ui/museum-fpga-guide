`timescale 1ns/1ps

// Same one-clock latency for fullscreen and thumbnail views. Borders, labels
// and hints are drawn later by the existing shared menu-font layer.
module thumbnail_overlay_24 #(parameter integer DIRECTORY_LAYOUT=0,
    parameter integer FULLSCREEN_THUMBNAILS=0,
    parameter integer ENABLE_THUMB_TRANSPARENCY=0,
    parameter integer FIXED_OPAQUE_THUMBNAILS=0) (
    input wire clk,rst_n,hsync,vsync,de,view_mode,
    input wire [9:0] pixel_x,
    input wire [23:0] rgb_in,
    input wire [1:0] thumbnail_transparency,
    output wire frame_start,consume_row,
    output wire [8:0] display_row,consumed_row,
    output wire [9:0] pixel_address,
    input wire [1:0] display_mask,
    input wire [31:0] pixel_data,
    output reg out_hs,out_vs,out_de,
    output reg [9:0] out_x,
    output wire [23:0] rgb_out
);
    reg vs_q,de_q;
    reg [8:0] line_y;
    reg [9:0] active_x;
    wire top_row=line_y>=96 && line_y<216;
    localparam integer DIRECTORY_TOP=FULLSCREEN_THUMBNAILS!=0 ? 8 : 64;
    wire [8:0] directory_row=line_y-DIRECTORY_TOP;
    wire [1:0] directory_entry=directory_row<88 ? 2'd0 : directory_row<176 ? 2'd1 : directory_row<264 ? 2'd2 : 2'd3;
    wire [8:0] directory_local=directory_row-(directory_entry==0 ? 0 : directory_entry==1 ? 88 : directory_entry==2 ? 176 : 264);
    wire directory_left=active_x>=24 && active_x<104 && line_y>=DIRECTORY_TOP && line_y<DIRECTORY_TOP+352 && directory_local<60;
    wire directory_right=active_x>=264 && active_x<584 && line_y>=120 && line_y<360;
    wire bottom_row=line_y>=256 && line_y<376;
    wire left_tile=active_x>=128 && active_x<288;
    wire right_tile=active_x>=352 && active_x<512;
    wire [7:0] local_x=right_tile ? active_x-352 : active_x-128;
    assign display_row=DIRECTORY_LAYOUT!=0 ? directory_row : (top_row ? line_y-96 : line_y-256+120);
    assign consumed_row=display_row;
    assign consume_row=view_mode && de_q && !de && (DIRECTORY_LAYOUT!=0 ? line_y>=DIRECTORY_TOP && line_y<DIRECTORY_TOP+352 : top_row || bottom_row);
    assign frame_start=vs_q && !vsync;
    wire [7:0] directory_x=directory_right ? (active_x-264)>>1 : (active_x-24)<<1;
    assign pixel_address=DIRECTORY_LAYOUT!=0 ? {display_row[0],directory_right,directory_x} :
        {display_row[0],right_tile,local_x};
    reg image_pixel_q,view_q;
    reg [23:0] passthrough_q;
    // Half-alpha uses nine-bit sums, preserving every channel without DSPs.
    wire [8:0] blend_r={1'b0,passthrough_q[23:16]}+{1'b0,pixel_data[31:24]};
    wire [8:0] blend_g={1'b0,passthrough_q[15:8]}+{1'b0,pixel_data[23:16]};
    wire [8:0] blend_b={1'b0,passthrough_q[7:0]}+{1'b0,pixel_data[15:8]};
    reg [1:0] alpha_q;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) alpha_q<=2'd2;
        else if(frame_start) alpha_q<=ENABLE_THUMB_TRANSPARENCY!=0 ? thumbnail_transparency : 2'd2;
    end
    function [7:0] blend_channel;
        input [7:0] back,front;
        input [1:0] alpha;
        reg [9:0] a,b,sum;
        begin
            a={2'b0,back};b={2'b0,front};
            case(alpha)
                0:sum=b<<2;
                1:sum=a+b+(b<<1);
                2:sum=(a+b)<<1;
                3:sum=b+a+(a<<1);
            endcase
            blend_channel=sum[9:2];
        end
    endfunction
    wire [23:0] alpha_rgb=FIXED_OPAQUE_THUMBNAILS!=0 ? pixel_data[31:8] : ENABLE_THUMB_TRANSPARENCY!=0 ? {
        blend_channel(passthrough_q[23:16],pixel_data[31:24],alpha_q),
        blend_channel(passthrough_q[15:8],pixel_data[23:16],alpha_q),
        blend_channel(passthrough_q[7:0],pixel_data[15:8],alpha_q)} :
        {blend_r[8:1],blend_g[8:1],blend_b[8:1]};
    assign rgb_out=FULLSCREEN_THUMBNAILS!=0 ?
        (image_pixel_q ? alpha_rgb : passthrough_q) :
        (view_q ? (image_pixel_q ? pixel_data[31:8] : 24'h1b222c) : passthrough_q);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vs_q<=1;de_q<=0;line_y<=0;active_x<=0;
            out_hs<=1;out_vs<=1;out_de<=0;out_x<=0;
            view_q<=0;image_pixel_q<=0;passthrough_q<=0;
        end else begin
            vs_q<=vsync;de_q<=de;
            if(!vsync) line_y<=0;
            else if(de_q && !de) line_y<=line_y+1'b1;
            if(!de) active_x<=0;else active_x<=active_x+1'b1;
            out_hs<=hsync;out_vs<=vsync;out_de<=de;out_x<=pixel_x;
            view_q<=view_mode;passthrough_q<=rgb_in;
            image_pixel_q<=view_mode && de && (DIRECTORY_LAYOUT!=0 ?
                (directory_left || (FULLSCREEN_THUMBNAILS==0 && directory_right)) && display_mask[directory_right] :
                (top_row || bottom_row) && (left_tile || right_tile) && display_mask[right_tile]);
        end
    end
endmodule
