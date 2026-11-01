`timescale 1ns/1ps

module hdmi_audio_symbol_core #(
    parameter integer ACR_INTERVAL_CYCLES = 25000
) (
    input  wire               pixel_clk,
    input  wire               rst_n,
    input  wire               video_hsync,
    input  wire               video_vsync,
    input  wire               video_de,
    input  wire [9:0]         video_x,
    input  wire [23:0]        video_rgb,
    input  wire               sample_valid,
    output wire               sample_ready,
    input  wire signed [15:0] sample_left,
    input  wire signed [15:0] sample_right,
    output wire [9:0]         channel0_symbol,
    output wire [9:0]         channel1_symbol,
    output wire [9:0]         channel2_symbol,
    output wire               sequence_error
);
    reg previous_vsync;

    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            previous_vsync <= 1'b1;
        end else begin
            previous_vsync <= video_vsync;
        end
    end

    // Fixed 640x480 timing: after negative VSYNC, 33 back-porch
    // lines precede 480 active lines. HS rises 48 pixels before x=0.
    // The existing color_bar counts VSYNC edges at H_FP: the HS rise
    // on the VSYNC-release line is count 1, so active lines are 34..513.
    // Never announce a Video Data Period on a vertical-blanking line.
    reg previous_hsync;
    reg [9:0] lines_after_vsync;
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            previous_hsync <= 1'b1;
            lines_after_vsync <= 10'd0;
        end else begin
            previous_hsync <= video_hsync;
            if (!video_vsync)
                lines_after_vsync <= 10'd0;
            else if (!previous_hsync && video_hsync && lines_after_vsync != 10'd1023)
                lines_after_vsync <= lines_after_vsync + 10'd1;
        end
    end
    wire next_line_active = lines_after_vsync >= 10'd34 &&
                            lines_after_vsync < 10'd514;
    wire video_preamble = next_line_active && video_x >= 10'd790 && video_x <= 10'd797;
    wire video_guard = next_line_active && video_x >= 10'd798;
    wire island_slot = video_x == 10'd652;
    wire info_emit = previous_vsync && !video_vsync;

    wire audio_valid, audio_ready;
    wire [23:0] audio_header;
    wire [7:0] audio_header_ecc;
    wire [223:0] audio_body;
    wire [31:0] audio_body_ecc;
    wire [7:0] packet_frame_base_unused;
    hdmi_audio_sample_packetizer u_audio_packetizer (
        .clk(pixel_clk), .rst_n(rst_n),
        .sample_valid(sample_valid), .sample_ready(sample_ready),
        .sample_left(sample_left), .sample_right(sample_right),
        .packet_valid(audio_valid), .packet_ready(audio_ready),
        .packet_header(audio_header),
        .packet_header_ecc(audio_header_ecc),
        .packet_body(audio_body), .packet_body_ecc(audio_body_ecc),
        .packet_frame_base(packet_frame_base_unused)
    );

    wire acr_valid, acr_ready;
    wire [23:0] acr_header;
    wire [7:0] acr_header_ecc;
    wire [223:0] acr_body;
    wire [31:0] acr_body_ecc;
    hdmi_audio_acr_packetizer #(
        .INTERVAL_CYCLES(ACR_INTERVAL_CYCLES),
        .ACR_N(20'd6144),
        .ACR_CTS(20'd25000)
    ) u_acr_packetizer (
        .clk(pixel_clk), .rst_n(rst_n),
        .packet_valid(acr_valid), .packet_ready(acr_ready),
        .packet_header(acr_header), .packet_header_ecc(acr_header_ecc),
        .packet_body(acr_body), .packet_body_ecc(acr_body_ecc)
    );

    wire info_valid, info_ready;
    wire [23:0] info_header;
    wire [7:0] info_header_ecc;
    wire [223:0] info_body;
    wire [31:0] info_body_ecc;
    hdmi_audio_infoframe_packetizer u_info_packetizer (
        .clk(pixel_clk), .rst_n(rst_n), .emit(info_emit),
        .packet_valid(info_valid), .packet_ready(info_ready),
        .packet_header(info_header),
        .packet_header_ecc(info_header_ecc),
        .packet_body(info_body), .packet_body_ecc(info_body_ecc)
    );

    wire packet_valid;
    wire packet_claim;
    wire packet_ready;
    wire [1:0] packet_source_unused;
    wire [23:0] packet_header;
    wire [7:0] packet_header_ecc;
    wire [223:0] packet_body;
    wire [31:0] packet_body_ecc;
    hdmi_audio_packet_scheduler u_packet_scheduler (
        .clk(pixel_clk), .rst_n(rst_n),
        .acr_valid(acr_valid), .acr_ready(acr_ready),
        .acr_header(acr_header), .acr_header_ecc(acr_header_ecc),
        .acr_body(acr_body), .acr_body_ecc(acr_body_ecc),
        .info_valid(info_valid), .info_ready(info_ready),
        .info_header(info_header), .info_header_ecc(info_header_ecc),
        .info_body(info_body), .info_body_ecc(info_body_ecc),
        .audio_valid(audio_valid), .audio_ready(audio_ready),
        .audio_header(audio_header), .audio_header_ecc(audio_header_ecc),
        .audio_body(audio_body), .audio_body_ecc(audio_body_ecc),
        .packet_valid(packet_valid), .packet_lock(packet_claim),
        .packet_ready(packet_ready),
        .packet_source(packet_source_unused),
        .packet_header(packet_header),
        .packet_header_ecc(packet_header_ecc),
        .packet_body(packet_body), .packet_body_ecc(packet_body_ecc)
    );

    wire [2:0] mode;
    wire [1:0] control0, control1, control2;
    wire [4:0] packet_pixel_index;
    wire [23:0] active_header;
    wire [7:0] active_header_ecc;
    wire [223:0] active_body;
    wire [31:0] active_body_ecc;
    wire sequence_active_unused;
    hdmi_data_island_scheduler u_island_scheduler (
        .clk(pixel_clk), .rst_n(rst_n),
        .video_active(video_de), .video_preamble(video_preamble),
        .video_guard(video_guard), .island_slot(island_slot),
        .hsync(video_hsync), .vsync(video_vsync),
        .packet_valid(packet_valid), .packet_ready(packet_ready),
        .packet_claim(packet_claim),
        .packet_header(packet_header),
        .packet_header_ecc(packet_header_ecc),
        .packet_body(packet_body), .packet_body_ecc(packet_body_ecc),
        .mode(mode), .channel0_control(control0),
        .channel1_control(control1), .channel2_control(control2),
        .packet_pixel_index(packet_pixel_index),
        .active_header(active_header),
        .active_header_ecc(active_header_ecc),
        .active_body(active_body), .active_body_ecc(active_body_ecc),
        .sequence_active(sequence_active_unused),
        .sequence_error(sequence_error)
    );

    wire [3:0] island0, island1, island2;
    hdmi_data_island_mapper u_island_mapper (
        .pixel_index(packet_pixel_index),
        .hsync(video_hsync), .vsync(video_vsync),
        .packet_header(active_header),
        .packet_header_ecc(active_header_ecc),
        .packet_body(active_body), .packet_body_ecc(active_body_ecc),
        .channel0_terc4(island0), .channel1_terc4(island1),
        .channel2_terc4(island2)
    );

    wire [9:0] tmds_lookup_address0,tmds_lookup_address1,tmds_lookup_address2;
    wire [15:0] tmds_lookup_data0,tmds_lookup_data1,tmds_lookup_data2;
    hdmi_tmds_lookup_rom u_tmds_lookup_rom (
        .clk(pixel_clk),
        .address0(tmds_lookup_address0),.address1(tmds_lookup_address1),.address2(tmds_lookup_address2),
        .data0(tmds_lookup_data0),.data1(tmds_lookup_data1),.data2(tmds_lookup_data2)
    );

    hdmi_tmds_lookup_channel #(.CHANNEL(0)) u_encoder0 (
        .clk(pixel_clk), .rst_n(rst_n), .mode(mode),
        .video_data(video_rgb[7:0]), .data_island_data(island0),
        .control_data(control0), .symbol(channel0_symbol),
        .lookup_address(tmds_lookup_address0),.lookup_data(tmds_lookup_data0)
    );
    hdmi_tmds_lookup_channel #(.CHANNEL(1)) u_encoder1 (
        .clk(pixel_clk), .rst_n(rst_n), .mode(mode),
        .video_data(video_rgb[15:8]), .data_island_data(island1),
        .control_data(control1), .symbol(channel1_symbol),
        .lookup_address(tmds_lookup_address1),.lookup_data(tmds_lookup_data1)
    );
    hdmi_tmds_lookup_channel #(.CHANNEL(2)) u_encoder2 (
        .clk(pixel_clk), .rst_n(rst_n), .mode(mode),
        .video_data(video_rgb[23:16]), .data_island_data(island2),
        .control_data(control2), .symbol(channel2_symbol),
        .lookup_address(tmds_lookup_address2),.lookup_data(tmds_lookup_data2)
    );
endmodule
