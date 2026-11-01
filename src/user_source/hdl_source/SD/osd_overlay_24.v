`timescale 1ns/1ps

// 24-bit wrapper for the status OSD. It reconstructs the active line number
// from the existing video sync bundle, so no extra video timing delay is added.
module osd_overlay_24 #(
    parameter integer OSD_X = 8,
    parameter integer OSD_Y = 8,
    parameter integer ENABLE_PAUSE_STATUS = 0,
    parameter integer INDEX_BITS=2
) (
    input wire clk, rst_n,
    input wire vsync,
    input wire de,
    input wire [23:0] rgb_in,
    input wire [9:0] pixel_x,
    input wire enable,
    input wire [INDEX_BITS-1:0] active_index,
    input wire auto_enabled,
    input wire [7:0] error_code,
    input wire [1:0] audio_status,
    input wire audio_paused,
    output wire [23:0] rgb_out,
    output wire de_out,
    output wire osd_active
);
    reg [11:0] line_y;
    reg de_q, vs_q;
    wire frame_start = vs_q && !vsync;
    wire [11:0] osd_rgb12;
    wire osd_hit;
    wire audio_hit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_y <= 0;
            de_q <= 0;
            vs_q <= 1;
        end else begin
            de_q <= de;
            vs_q <= vsync;
            if (!vsync)
                line_y <= 0;
            else if (de_q && !de)
                line_y <= line_y + 1'b1;
        end
    end

    status_osd_overlay #(.OSD_X(OSD_X), .OSD_Y(OSD_Y),.INDEX_BITS(INDEX_BITS),.TWO_DIGITS(INDEX_BITS>2)) u_status_osd (
        .clk(clk), .rst_n(rst_n), .frame_start(frame_start),
        .active_index(active_index), .auto_enabled(auto_enabled),
        .error_code(error_code), .in_de(de && enable),
        .in_rgb({rgb_in[23:20], rgb_in[15:12], rgb_in[7:4]}),
        .pixel_x({2'b00, pixel_x}), .pixel_y(line_y),
        .out_rgb(osd_rgb12), .out_de(), .osd_pixel(osd_hit)
    );

    audio_status_osd #(.OSD_X(OSD_X), .OSD_Y(OSD_Y+12),
        .ENABLE_PAUSE_STATUS(ENABLE_PAUSE_STATUS)) u_audio_status_osd (
        .clk(clk), .rst_n(rst_n), .frame_start(frame_start),
        .status(audio_status),.paused(audio_paused), .in_de(de && enable),
        .pixel_x({2'b00, pixel_x}), .pixel_y(line_y),
        .osd_pixel(audio_hit)
    );

    assign rgb_out = osd_hit ?
        {osd_rgb12[11:8], osd_rgb12[11:8],
         osd_rgb12[7:4], osd_rgb12[7:4],
         osd_rgb12[3:0], osd_rgb12[3:0]} :
         audio_hit ? 24'h00ffff : rgb_in;
    assign de_out = de;
    assign osd_active = osd_hit || audio_hit;
endmodule
