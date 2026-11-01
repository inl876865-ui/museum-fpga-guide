`timescale 1ns/1ps

module rgb_video_adapter #(
    parameter HS_IN_ACTIVE_LOW = 1,
    parameter VS_IN_ACTIVE_LOW = 1,
    parameter HS_OUT_ACTIVE_LOW = 1,
    parameter VS_OUT_ACTIVE_LOW = 1,
    parameter VIDEO_DELAY = 0
) (
    input wire pclk,
    input wire rst_n,
    input wire hs_in,
    input wire vs_in,
    input wire de_in,
    input wire [23:0] rgb_in,
    output wire video_clk,
    output wire pixel_consume,
    output wire video_hs,
    output wire video_vs,
    output wire video_de,
    output reg [23:0] video_rgb
);
    wire hs_active = HS_IN_ACTIVE_LOW ? !hs_in : hs_in;
    wire vs_active = VS_IN_ACTIVE_LOW ? !vs_in : vs_in;
    wire hs_level = HS_OUT_ACTIVE_LOW ? !hs_active : hs_active;
    wire vs_level = VS_OUT_ACTIVE_LOW ? !vs_active : vs_active;
    reg [VIDEO_DELAY:0] hs_d, vs_d, de_d;
    wire rgb_valid;
    assign video_clk = pclk;
    assign video_hs = hs_d[VIDEO_DELAY];
    assign video_vs = vs_d[VIDEO_DELAY];
    assign video_de = de_d[VIDEO_DELAY];

    generate
        if (VIDEO_DELAY >= 2) begin : g_fifo_delay
            assign pixel_consume = de_d[VIDEO_DELAY-2];
            assign rgb_valid = de_d[VIDEO_DELAY-1];
        end else begin : g_direct
            assign pixel_consume = de_in;
            assign rgb_valid = de_in;
        end
    endgenerate

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            hs_d <= {(VIDEO_DELAY+1){HS_OUT_ACTIVE_LOW ? 1'b1 : 1'b0}};
            vs_d <= {(VIDEO_DELAY+1){VS_OUT_ACTIVE_LOW ? 1'b1 : 1'b0}};
            de_d <= 0;
            video_rgb <= 24'd0;
        end else begin
            hs_d <= (hs_d << 1) | hs_level;
            vs_d <= (vs_d << 1) | vs_level;
            de_d <= (de_d << 1) | de_in;
            video_rgb <= rgb_valid ? rgb_in : 24'd0;
        end
    end
endmodule
