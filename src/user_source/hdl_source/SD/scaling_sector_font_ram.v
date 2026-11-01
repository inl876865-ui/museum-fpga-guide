`timescale 1ns/1ps
// Unit prototype, not connected to any existing interface.
// A: pixel-clock immutable glyph bytes0..127. B: SD-clock buffer128..639.
module scaling_sector_font_ram(
    input wire pixel_clk,sd_clk,
    input wire [6:0] font_address,
    output wire [7:0] font_byte,
    input wire [8:0] sector_address,
    input wire sector_write,
    input wire [7:0] sector_write_data,
    output wire [7:0] sector_read_data
);
    wire [9:0] sector_physical_address={1'b0,sector_address}+10'd128;
    wire [8:0] font_word,sector_word;
    assign font_byte=font_word[7:0];
    assign sector_read_data=sector_word[7:0];
    EG_PHY_BRAM #(
        .MODE("DP8K"),.DATA_WIDTH_A("9"),.DATA_WIDTH_B("9"),
        .CEAMUX("1"),.CEBMUX("1"),.OCEAMUX("1"),.OCEBMUX("1"),
        .CSA0("1"),.CSA1("1"),.CSA2("1"),.CSB0("1"),.CSB1("1"),.CSB2("1"),
        .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.RESETMODE("ASYNC"),
        .RSTAMUX("0"),.RSTBMUX("0"),.WEAMUX("0"),.WEBMUX("SIG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
        .INIT_00(256'h00200c3c380620018000fe7f400040184012400644200420fc3f800100010000),
        .INIT_01(256'h0000380008400864087c08644864c864887c0864fe65fe65087c080008000000),
        .INIT_02(256'h00028003800080008000fe7f8001c0006000f00f00200620fe3f800100010000),
        .INIT_03(256'h00000000b00990099009fe7f3008fc7f0002f81ff81f1810f81f6004fc3f6004)
    ) u_shared_ram(
        .clka(pixel_clk),.clkb(sd_clk),
        .addra({3'b000,font_address,3'b111}),
        .addrb({sector_physical_address,3'b111}),
        .dia(9'd0),.dib({1'b0,sector_write_data}),.doa(font_word),.dob(sector_word),
        .wea(1'b0),.web(sector_write),.cea(1'b1),.ceb(1'b1),
        .ocea(1'b1),.oceb(1'b1),.rsta(1'b0),.rstb(1'b0),.csa(3'b111),.csb(3'b111)
    );
endmodule
