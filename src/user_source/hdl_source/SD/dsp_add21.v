`timescale 1ns/1ps
// One physical unsigned multiplier performs the low9 sum. Remaining high12
// arithmetic includes its exact carry; the full result remains modulo2^21.
module dsp_add21(input wire [20:0] a,b,output wire [20:0] sum);
    wire [9:0] low_sum;
    wire [11:0] high_sum=a[20:9]+b[20:9]+low_sum[9];
    dsp_sum9 u_low(.a(a[8:0]),.b(b[8:0]),.sum(low_sum));
    assign sum={high_sum,low_sum[8:0]};
endmodule
