`timescale 1ns/1ps

// Hold the SD-domain target until a pixel-domain frame boundary commits it.
// The acknowledgement returns only after active_index has changed.
module media_frame_commit #(parameter integer ENABLE_BOUND_CANCEL=0,
    parameter integer ENABLE_REQUEST_GUARD=0) (
    input  wire       sd_clk,
    input  wire       sd_rst,
    input  wire       request_toggle,
    input  wire [1:0] request_index,
    input  wire request_is_bound,
    input  wire [2:0] request_track,
    input  wire bound_allowed_pixel,
    input  wire [2:0] bound_track_pixel,
    output wire commit_applied,
    output wire       acknowledge_toggle,
    input  wire       pixel_clk,
    input  wire       pixel_rst,
    input  wire       frame_start,
    output reg  [1:0] active_index,
    output reg        active_valid
);
    (* async_reg = "true" *) reg [1:0] request_sync;
    (* async_reg = "true" *) reg [1:0] index_sync0, index_sync1;
    (* async_reg = "true" *) reg [1:0] acknowledge_sync;
    reg acknowledge_pixel,applied_pixel;
    // The SD80/pixel clocks can have adjacent edges only 2.5 ns apart.
    // One extra request stage lets the held index/track finish two captures
    // before a frame boundary consumes them. Legacy instances keep two stages.
    reg request_guarded;
    wire request_seen=ENABLE_REQUEST_GUARD!=0 ? request_guarded : request_sync[1];
    (* async_reg="true" *) reg [1:0] bound_sync,applied_sync;
    (* async_reg="true" *) reg [2:0] track_sync0,track_sync1;

    always @(posedge pixel_clk or posedge pixel_rst) begin
        if (pixel_rst) begin
            request_sync <= 2'b00;
            request_guarded <= 1'b0;
            index_sync0 <= 2'd0;
            index_sync1 <= 2'd0;
            acknowledge_pixel <= 1'b0;
            active_index <= 2'd0;
            active_valid <= 1'b0;applied_pixel<=0;bound_sync<=0;track_sync0<=0;track_sync1<=0;
        end else begin
            request_sync <= {request_sync[0], request_toggle};
            request_guarded <= request_sync[1];
            bound_sync<={bound_sync[0],request_is_bound};track_sync0<=request_track;track_sync1<=track_sync0;
            index_sync0 <= request_index;
            index_sync1 <= index_sync0;
            if (frame_start && request_seen != acknowledge_pixel) begin
                if(ENABLE_BOUND_CANCEL==0 || !bound_sync[1] ||
                   (bound_allowed_pixel && track_sync1==bound_track_pixel)) begin
                    active_index<=index_sync1;active_valid<=1;applied_pixel<=1;
                end else applied_pixel<=0;
                acknowledge_pixel <= request_seen;
            end
        end
    end

    always @(posedge sd_clk or posedge sd_rst) begin
        if (sd_rst) begin acknowledge_sync<=0;applied_sync<=0;end
        else begin
            acknowledge_sync<={acknowledge_sync[0],acknowledge_pixel};
            applied_sync<={applied_sync[0],applied_pixel};
        end
    end
    assign acknowledge_toggle = acknowledge_sync[1];
    assign commit_applied=ENABLE_BOUND_CANCEL==0 ? 1'b1 : applied_sync[1];
endmodule
