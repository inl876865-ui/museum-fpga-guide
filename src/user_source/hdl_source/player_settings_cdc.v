`timescale 1ns/1ps
// Bundled-data toggle handshake. Shared system reset asserts both resets;
// each clock domain releases its own reset synchronously.
module player_settings_cdc #(
    parameter integer WIDTH = 8,
    parameter [WIDTH-1:0] RESET_VALUE = 128
) (
    input wire src_clk, src_rst,
    input wire [WIDTH-1:0] src_value,
    input wire dst_clk, dst_rst,
    output reg [WIDTH-1:0] dst_value,
    output wire src_ready
);
    reg [WIDTH-1:0] held_value;
    reg request, acknowledge;
    (* async_reg = "true" *) reg [1:0] ack_sync, req_sync;
    reg capture_pending;
    assign src_ready=request==ack_sync[1] && src_value==held_value;
    always @(posedge src_clk or posedge src_rst) begin
        if (src_rst) begin
            held_value <= RESET_VALUE;
            request <= 0;
            ack_sync <= 0;
        end else begin
            ack_sync <= {ack_sync[0], acknowledge};
            if (request == ack_sync[1] && src_value != held_value) begin
                held_value <= src_value;
                request <= ~request;
            end
        end
    end
    always @(posedge dst_clk or posedge dst_rst) begin
        if (dst_rst) begin
            req_sync <= 0;
            acknowledge <= 0;
            capture_pending <= 0;
            dst_value <= RESET_VALUE;
        end else begin
            req_sync <= {req_sync[0], request};
            if (!capture_pending && req_sync[1] != acknowledge)
                capture_pending <= 1;
            else if (capture_pending) begin
                dst_value <= held_value;
                acknowledge <= req_sync[1];
                capture_pending <= 0;
            end
        end
    end
endmodule
