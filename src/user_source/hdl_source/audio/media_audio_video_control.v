`timescale 1ns/1ps

// Adapt the existing 640x480 timing and committed picture number to the
// lesson's unmodified audio bridge. Active pixels use x=0..639; blanking
// uses x=640..799, including vertical blanking lines.
module media_audio_video_control #(
    parameter [7:0] VOLUME = 8'd128,
    parameter integer STATE_BITS=4,
    parameter integer MAX_IMAGES=4
) (
    input  wire       pixel_clk,
    input  wire       rst,
    input  wire       video_hsync,
    input  wire       video_vsync,
    input  wire [STATE_BITS-1:0] state_code,
    input  wire       display_valid,
    output wire [9:0] video_x,
    output reg        timing_locked,
    output reg  [1:0] media_id,
    output reg [STATE_BITS-2:0] image_index,
    output wire [7:0] volume
);
    reg hsync_q;
    reg vsync_q;
    reg [9:0] x_count;
    reg [STATE_BITS-1:0] state_sync0;
    reg [STATE_BITS-1:0] state_sync1;
    reg [STATE_BITS-1:0] state_sync2;
    reg [STATE_BITS-1:0] state_stable;
    reg [1:0] valid_sync;
    reg media_valid;

    // HS is low at x=656..751. Correct the coordinate in the same cycle
    // as its rising edge, then count through the 48-pixel back porch.
    assign video_x = (video_hsync && !hsync_q) ? 10'd752 : x_count;
    assign volume = (media_valid && valid_sync[1]) ? VOLUME : 8'd0;

    always @(posedge pixel_clk or posedge rst) begin
        if (rst) begin
            hsync_q <= 1'b0;
            vsync_q <= 1'b0;
            x_count <= 10'd0;
            timing_locked <= 1'b0;
        end else begin
            hsync_q <= video_hsync;
            vsync_q <= video_vsync;
            if (video_hsync && !hsync_q) begin
                x_count <= 10'd753;
                timing_locked <= 1'b1;
            end else if (x_count == 10'd799) begin
                x_count <= 10'd0;
            end else begin
                x_count <= x_count + 10'd1;
            end
        end
    end

    // state_code is a slowly changing committed index (1..4), not a key
    // pulse. Synchronize it and require two equal observations before use.
    // Latch at vertical sync, when the original reader starts a new frame.
    always @(posedge pixel_clk or posedge rst) begin
        if (rst) begin
            state_sync0 <= 4'd0;
            state_sync1 <= 4'd0;
            state_sync2 <= 4'd0;
            state_stable <= 4'd0;
            valid_sync <= 2'b00;
            media_id <= 2'd0;image_index<=0;
            media_valid <= 1'b0;
        end else begin
            state_sync0 <= state_code;
            state_sync1 <= state_sync0;
            state_sync2 <= state_sync1;
            valid_sync <= {valid_sync[0], display_valid};
            if (state_sync1 == state_sync2)
                state_stable <= state_sync2;

            if (!valid_sync[1]) begin
                media_valid <= 1'b0;
            end else if (vsync_q && !video_vsync &&
                         state_stable >= 4'd1 && state_stable <= MAX_IMAGES) begin
                media_id <= state_stable[1:0] - 2'd1;
                image_index<=state_stable-1'b1;
                media_valid <= 1'b1;
            end
        end
    end
endmodule
