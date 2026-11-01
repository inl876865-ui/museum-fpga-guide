`timescale 1ns/1ps
// Keep the narration valid/ready contract; cue starvation contributes zero.
module transition_cue_mixer (
    input wire clk,rst_n,
    input wire source_valid,
    output wire source_ready,
    input wire signed [15:0] source_left,source_right,cue_sample,
    input wire cue_valid,
    output wire cue_ready,
    input wire [7:0] volume,
    output wire mixed_valid,
    input wire mixed_ready,
    output wire signed [15:0] mixed_left,mixed_right
);
    wire signed [24:0] scaled_cue=cue_sample*$signed({1'b0,volume});
    wire signed [16:0] cue_level=cue_valid ? scaled_cue >>> 9 : 17'sd0;
    wire signed [16:0] left_sum=$signed({source_left[15],source_left})+cue_level;
    wire signed [16:0] right_sum=$signed({source_right[15],source_right})+cue_level;
    function [15:0] clamp;
        input signed [16:0] value;
        begin clamp=value>32767 ? 16'h7fff : value< -32768 ? 16'h8000 : value[15:0];end
    endfunction
    // The caller captures both channels in its existing stalled-sample register.
    assign source_ready=mixed_ready;
    assign cue_ready=mixed_ready && source_valid;
    assign mixed_valid=source_valid;
    assign mixed_left=clamp(left_sum);
    assign mixed_right=clamp(right_sum);
endmodule
