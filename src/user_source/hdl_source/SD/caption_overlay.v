`timescale 1ns/1ps
// Single-line16px subtitle ink from the existing24px CAP bitmap layout. Coordinate and RGB attributes traverse the same two stages.
// The supplied bitmap RAM is synchronous to clk with one clock of read latency.
module caption_overlay #(
    parameter integer ENABLE_CAPTION=0,
    parameter integer ENABLE_FILE_COLOR=0,
    parameter integer LEFT=0,TOP=368,VIEW_WIDTH=640,
    parameter [23:0] INK=24'he8eef2
)(
    input wire clk,rst_n,
    input wire in_hs,in_vs,in_de,
    input wire [9:0] in_x,
    input wire [23:0] rgb_in,
    input wire visible,bitmap_bank,
    input wire [9:0] bitmap_width,
    input wire [2:0] color_id,
    input wire signed [11:0] text_x,
    output wire [11:0] bitmap_address,
    output wire bitmap_read_bank,
    input wire [7:0] bitmap_byte,
    output wire out_hs,out_vs,out_de,
    output wire [9:0] out_x,
    output wire [23:0] rgb_out
);
    generate if(ENABLE_CAPTION!=0) begin : g_caption
        // DE defines the visible columns. Keep HDMI packet x untouched at out_x.
        reg [9:0] active_x;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) active_x<=0;
            else if(!in_de) active_x<=0;
            else active_x<=active_x+1'b1;
        end
        reg [8:0] line_y;
        reg de_q;
        reg [11:0] row_base;
        wire [6:0] row_bytes=bitmap_width[9:3];
        // Read source samples0,1,3,4,...22:24 stored columns become16 pixels.
        // Source files render native16 glyphs and expand them24/16 beforehand.
        // Legacy24 glyph CAPs remain readable, with nearest-neighbor reduction.
        wire signed [12:0] display_x=$signed({3'd0,active_x})-$signed({text_x[11],text_x});
        wire signed [12:0] source_x=display_x+(display_x>>>1);
        wire hit=visible && in_de && active_x>=LEFT && active_x<LEFT+VIEW_WIDTH &&
                 line_y>=TOP && line_y<TOP+16 && display_x>=0 &&
                 source_x<$signed({3'd0,bitmap_width});
        assign bitmap_address=hit ? row_base+{5'd0,source_x[9:3]} : 12'd0;
        assign bitmap_read_bank=bitmap_bank;
        reg hs_q,vs_q,pixel_de_q,hit_q;
        reg [9:0] x_q;
        reg [23:0] rgb_q,output_rgb;
        reg [2:0] bit_q,color_q;
        reg [23:0] file_ink;
        always @* begin
            case(color_q)
                3'd1:file_ink=24'hffffff;
                3'd2:file_ink=24'hffff00;
                3'd3:file_ink=24'h00ffff;
                3'd4:file_ink=24'h00ff00;
                3'd5:file_ink=24'hff0000;
                3'd6:file_ink=24'h3399ff;
                3'd7:file_ink=24'hff66cc;
                default:file_ink=INK;
            endcase
        end
        reg output_hs,output_vs,output_de;
        reg [9:0] output_x;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                line_y<=0;de_q<=0;row_base<=0;
                hs_q<=1;vs_q<=1;pixel_de_q<=0;hit_q<=0;x_q<=0;rgb_q<=0;bit_q<=0;color_q<=0;
                output_hs<=1;output_vs<=1;output_de<=0;output_x<=0;output_rgb<=0;
            end else begin
                de_q<=in_de;
                if(!in_vs) begin line_y<=0;row_base<=0;end
                else if(de_q && !in_de) begin
                    line_y<=line_y+1'b1;
                    if(line_y==TOP-1) row_base<=0;
                    // Adjacent output rows advance one,two,one,two source rows.
                    // TOP=368 is even; this parity also holds for any even TOP.
                    else if(line_y>=TOP && line_y<TOP+16)
                        row_base<=row_base+(line_y[0] ? {4'd0,row_bytes,1'b0} : {5'd0,row_bytes});
                end
                hs_q<=in_hs;vs_q<=in_vs;pixel_de_q<=in_de;x_q<=in_x;
                rgb_q<=rgb_in;hit_q<=hit;bit_q<=source_x[2:0];color_q<=color_id;
                output_hs<=hs_q;output_vs<=vs_q;output_de<=pixel_de_q;output_x<=x_q;
                output_rgb<=hit_q && bitmap_byte[7-bit_q] ? (ENABLE_FILE_COLOR!=0 ? file_ink : INK) : rgb_q;
            end
        end
        assign out_hs=output_hs;assign out_vs=output_vs;assign out_de=output_de;
        assign out_x=output_x;assign rgb_out=output_rgb;
    end else begin : g_disabled
        assign bitmap_address=0;assign bitmap_read_bank=0;
        assign out_hs=in_hs;assign out_vs=in_vs;assign out_de=in_de;
        assign out_x=in_x;assign rgb_out=rgb_in;
    end endgenerate
endmodule
