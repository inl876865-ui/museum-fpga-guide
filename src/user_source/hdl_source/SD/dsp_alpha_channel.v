`timescale 1ns/1ps
// Exact four-level alpha. Both sums are coded through an unsigned multiplier.
module dsp_alpha_channel(input wire [7:0] back,front,input wire [1:0] level,output wire [7:0] result);
    wire [9:0] base,weighted;
    wire [7:0] extra=level[1] ? back : front;
    dsp_sum9 u_base(.a({1'b0,back}),.b({1'b0,front}),.sum(base));
    dsp_sum9 u_weighted(.a(base[8:0]),.b({extra,1'b0}),.sum(weighted));
    assign result=level==0 ? front : level==2 ? base[8:1] : weighted[9:2];
endmodule
