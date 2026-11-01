`timescale 1ns/1ps

// Keep the previous bank available while the committed new bank is revealed.
// The descriptor changes in vertical blanking and remains stable in active video.
module video_wipe_control #(
    parameter integer FRAME_WIDTH = 640,
    parameter integer WIPE_FRAMES = 16
) (
    input  wire       pixel_clk,
    input  wire       pixel_rst,
    input  wire       frame_start,
    input  wire       active_valid,
    input  wire [1:0] active_index,
    input  wire       auto_frame_commit,
    output reg        wipe_active,
    output reg  [1:0] wipe_old_index,
    output reg  [1:0] wipe_new_index,
    output reg  [9:0] wipe_boundary
);
    localparam integer WIPE_STEP = FRAME_WIDTH / WIPE_FRAMES;
    (* async_reg = "true" *) reg [1:0] auto_sync;
    reg active_valid_q;
    reg [1:0] active_index_q;
    wire index_changed = active_valid_q && active_valid &&
                         active_index != active_index_q;

    always @(posedge pixel_clk or posedge pixel_rst) begin
        if (pixel_rst) begin
            auto_sync <= 0;
            active_valid_q <= 0;
            active_index_q <= 0;
            wipe_active <= 0;
            wipe_old_index <= 0;
            wipe_new_index <= 0;
            wipe_boundary <= 0;
        end else begin
            auto_sync <= {auto_sync[0], auto_frame_commit};
            active_valid_q <= active_valid;
            active_index_q <= active_index;
            if (index_changed) begin
                if (auto_sync[1]) begin
                    wipe_active <= 1;
                    wipe_old_index <= active_index_q;
                    wipe_new_index <= active_index;
                    wipe_boundary <= 0;
                end else begin
                    wipe_active <= 0;
                    wipe_boundary <= 0;
                end
            end else if (frame_start && wipe_active) begin
                if (wipe_boundary >= FRAME_WIDTH)
                    wipe_active <= 0;
                else
                    wipe_boundary <= wipe_boundary + WIPE_STEP;
            end
        end
    end
endmodule
