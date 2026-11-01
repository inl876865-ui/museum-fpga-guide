`timescale 1ns/1ps

// Picture-only processing. The two-cycle RGB/sync bundle precedes transitions
// and overlays. Runtime parameters commit together during vertical blanking.
module brightness_contrast_adjust (
    input wire clk,rst_n,frame_start,
    input wire [7:0] brightness,contrast,
    input wire in_hs,in_vs,in_de,
    input wire [9:0] in_x,
    input wire [23:0] rgb_in,
    output reg out_hs,out_vs,out_de,
    output reg [9:0] out_x,
    output reg [23:0] rgb_out
);
    reg [7:0] brightness_q,contrast_q,brightness_pipe;
    reg signed [17:0] red_product,green_product,blue_product;
    reg hs_pipe,vs_pipe,de_pipe;
    reg [9:0] x_pipe;
    wire signed [8:0] red_center=$signed({1'b0,rgb_in[23:16]})-9'sd128;
    wire signed [8:0] green_center=$signed({1'b0,rgb_in[15:8]})-9'sd128;
    wire signed [8:0] blue_center=$signed({1'b0,rgb_in[7:0]})-9'sd128;
    wire signed [8:0] contrast_factor=$signed({1'b0,contrast_q});
    function [7:0] clip_contrast;
        input signed [17:0] product;
        reg signed [17:0] value;
        begin
            value=(product >>> 7)+18'sd128;
            clip_contrast=value<0 ? 8'd0 : value>255 ? 8'd255 : value[7:0];
        end
    endfunction
    wire [7:0] red_clipped=clip_contrast(red_product);
    wire [7:0] green_clipped=clip_contrast(green_product);
    wire [7:0] blue_clipped=clip_contrast(blue_product);
    wire [15:0] red_bright=red_clipped*brightness_pipe;
    wire [15:0] green_bright=green_clipped*brightness_pipe;
    wire [15:0] blue_bright=blue_clipped*brightness_pipe;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            brightness_q<=255;contrast_q<=128;brightness_pipe<=255;
            red_product<=0;green_product<=0;blue_product<=0;
            hs_pipe<=1;vs_pipe<=1;de_pipe<=0;x_pipe<=0;
            out_hs<=1;out_vs<=1;out_de<=0;out_x<=0;rgb_out<=0;
        end else begin
            if(frame_start) begin brightness_q<=brightness;contrast_q<=contrast;end
            red_product<=red_center*contrast_factor;
            green_product<=green_center*contrast_factor;
            blue_product<=blue_center*contrast_factor;
            brightness_pipe<=brightness_q;
            hs_pipe<=in_hs;vs_pipe<=in_vs;de_pipe<=in_de;x_pipe<=in_x;
            out_hs<=hs_pipe;out_vs<=vs_pipe;out_de<=de_pipe;out_x<=x_pipe;
            // Full brightness bypass is bit-exact; zero brightness is black.
            rgb_out<=brightness_pipe==255 ? {red_clipped,green_clipped,blue_clipped} :
                {red_bright[15:8],green_bright[15:8],blue_bright[15:8]};
        end
    end
endmodule
