`timescale 1ns/1ps

// Automatic image changes fade the old bank out and the new bank in.
// Manual navigation passes through at full brightness on its frame boundary.
module video_auto_fade_control #(
    parameter integer FADE_FRAMES = 4
) (
    input  wire       pixel_clk,
    input  wire       pixel_rst,
    input  wire       frame_start,
    input  wire       active_valid,
    input  wire [1:0] active_index,
    input  wire       auto_frame_commit,
    input  wire [1:0] fade_level,
    output wire [1:0] read_index,
    output reg  [7:0] alpha,
    output wire       fade_active
);
    localparam [1:0] S_IDLE=0, S_OUT=1, S_IN=2;
    localparam integer STEP=256/FADE_FRAMES;
    reg [1:0] state;
    reg [4:0] step_count;
    reg [4:0] frame_limit;
    reg [1:0] fade_level_latched;
    reg [1:0] old_index;
    reg [1:0] active_index_q;
    reg active_valid_q;
    (* async_reg = "true" *) reg [1:0] auto_sync;
    wire index_changed = active_valid_q && active_valid &&
                         active_index != active_index_q;

    assign read_index = state == S_OUT ? old_index : active_index;
    assign fade_active = state != S_IDLE;

    function [7:0] fade_alpha;
        input [4:0] count;
        input [1:0] level;
        begin
            case (level)
                2'd2: fade_alpha = {count[2:0],5'b0};
                2'd3: fade_alpha = {count[3:0],4'b0};
                default: fade_alpha = count * STEP;
            endcase
        end
    endfunction

    always @(posedge pixel_clk or posedge pixel_rst) begin
        if (pixel_rst) begin
            state <= S_IDLE;
            step_count <= 0;
            frame_limit <= FADE_FRAMES;
            fade_level_latched <= 2'd1;
            old_index <= 0;
            active_index_q <= 0;
            active_valid_q <= 0;
            auto_sync <= 0;
            alpha <= 8'hff;
        end else begin
            auto_sync <= {auto_sync[0], auto_frame_commit};
            active_valid_q <= active_valid;
            active_index_q <= active_index;
            if (index_changed) begin
                if (auto_sync[1] && fade_level != 0) begin
                    old_index <= active_index_q;
                    state <= S_OUT;
                    frame_limit <= fade_level == 2'd3 ? 5'd16 :
                                   fade_level == 2'd2 ? 5'd8 : FADE_FRAMES;
                    fade_level_latched <= fade_level;
                    step_count <= fade_level == 2'd3 ? 5'd16 :
                                  fade_level == 2'd2 ? 5'd8 : FADE_FRAMES;
                    alpha <= 8'hff;
                end else begin
                    state <= S_IDLE;
                    alpha <= 8'hff;
                end
            end else if (frame_start) begin
                case (state)
                    S_OUT: begin
                        if (step_count == 1) begin
                            state <= S_IN;
                            step_count <= 0;
                            alpha <= 0;
                        end else begin
                            step_count <= step_count - 1'b1;
                            alpha <= fade_alpha(step_count - 1'b1, fade_level_latched);
                        end
                    end
                    S_IN: begin
                        if (step_count >= frame_limit - 1'b1) begin
                            state <= S_IDLE;
                            alpha <= 8'hff;
                        end else begin
                            step_count <= step_count + 1'b1;
                            alpha <= fade_alpha(step_count + 1'b1, fade_level_latched);
                        end
                    end
                    default: alpha <= 8'hff;
                endcase
            end
        end
    end
endmodule
