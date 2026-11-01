`timescale 1ns/1ps

// Separate four-glyph label ROM. The original 128-glyph menu ROM is unchanged.
// Each row is MSB-left; the output latency matches screen_menu_font_rom.
module caption_label_font (
    input wire clk,
    input wire [1:0] glyph,
    input wire [3:0] row,
    output reg [15:0] pixels
);
    (* rom_style="distributed" *) reg [15:0] font_rows [0:63];
    function [255:0] glyph_bitmap;
        input [1:0] code;
        begin case(code)
            2'd0: glyph_bitmap=256'h0000010001803ffc2004204406401240184000407ffe0080012006383c0c2000; // 实
            2'd1: glyph_bitmap=256'h0000000800087c0865fe65fe64087c8864c8644864087c086408400800380000; // 时
            2'd2: glyph_bitmap=256'h0000010001803ffe200620000ff0006000c001807ffe00800080008003800200; // 字
            2'd3: glyph_bitmap=256'h04603ffc04601ff810181ff81ff802007ffc08307ffe0990099009b000000000; // 幕
        endcase end
    endfunction
    integer code_index,row_index;
    reg [255:0] init_bitmap;
    initial begin
        for(code_index=0;code_index<4;code_index=code_index+1) begin
            init_bitmap=glyph_bitmap(code_index);
            for(row_index=0;row_index<16;row_index=row_index+1)
                font_rows[code_index*16+row_index]=init_bitmap >> ((15-row_index)*16);
        end
    end
    always @(posedge clk) pixels<=font_rows[{glyph,row}];
endmodule
