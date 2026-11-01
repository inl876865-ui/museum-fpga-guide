`timescale 1ns/1ps

module video_timing_ctrl #(
    parameter H_ACT = 640, H_FP = 16, H_SYNC = 96, H_BP = 48,
    parameter V_ACT = 480, V_FP = 10, V_SYNC = 2, V_BP = 33,
    parameter ACTIVE_LAST = 1
) (
    input wire pclk,
    input wire rst_n,
    output wire hsync,
    output wire vsync,
    output wire de,
    output reg [11:0] x,
    output reg [11:0] y
);
    localparam H_TOTAL = H_ACT + H_FP + H_SYNC + H_BP;
    localparam V_TOTAL = V_ACT + V_FP + V_SYNC + V_BP;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 0;
            y <= 0;
        end else if (x == H_TOTAL - 1) begin
            x <= 0;
            y <= (y == V_TOTAL - 1) ? 0 : y + 1'b1;
        end else begin
            x <= x + 1'b1;
        end
    end

    assign de = ACTIVE_LAST ?
                (x >= H_TOTAL - H_ACT && y >= V_TOTAL - V_ACT) :
                (x < H_ACT && y < V_ACT);
    assign hsync = ACTIVE_LAST ?
                   !(x >= H_FP && x < H_FP + H_SYNC) :
                   !(x >= H_ACT + H_FP && x < H_ACT + H_FP + H_SYNC);
    assign vsync = ACTIVE_LAST ?
                   !(y >= V_FP && y < V_FP + V_SYNC) :
                   !(y >= V_ACT + V_FP && y < V_ACT + V_FP + V_SYNC);
endmodule
