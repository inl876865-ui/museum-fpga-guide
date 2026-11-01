`timescale 1ns/1ps

// One video stream: fade to/from black or reveal the new frame from black.
// Combinational output keeps RGB aligned with the existing HS/VS/DE pipeline.
module video_transition_pixel #(
    parameter integer H_ACTIVE = 640,
    parameter integer FADE_FRAMES = 16
) (
    input  wire [23:0] rgb_in,
    input  wire [9:0]  pixel_x,
    input  wire [7:0]  alpha,
    input  wire        wipe_active,
    input  wire [4:0]  ramp,
    output wire [23:0] rgb_out
);
    wire [15:0] red_scaled   = rgb_in[23:16] * alpha;
    wire [15:0] green_scaled = rgb_in[15:8] * alpha;
    wire [15:0] blue_scaled  = rgb_in[7:0] * alpha;
    wire [23:0] fade_rgb = alpha == 8'hff ? rgb_in :
                           {red_scaled[15:8], green_scaled[15:8], blue_scaled[15:8]};
    wire [9:0] wipe_boundary = ramp * (H_ACTIVE / FADE_FRAMES);

    assign rgb_out = wipe_active ?
                     (pixel_x < wipe_boundary ? rgb_in : 24'd0) : fade_rgb;
endmodule
