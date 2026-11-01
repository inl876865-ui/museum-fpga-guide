`timescale 1ns/1ps
// Private lookup adapter. The public legacy encoder remains available unchanged.
module hdmi_tmds_lookup_channel #(parameter integer CHANNEL=0) (
    input wire clk,rst_n,
    input wire [2:0] mode,
    input wire [7:0] video_data,
    input wire [3:0] data_island_data,
    input wire [1:0] control_data,
    output wire [9:0] symbol,
    output reg [9:0] lookup_address,
    input wire [15:0] lookup_data
);
    localparam [1:0] CHANNEL_INDEX=CHANNEL;
    reg signed [5:0] disparity;
    reg lookup_valid;
    // The ROM holds the preceding symbol's delta. Retiming only the feedback
    // register puts the exact current disparity before this clock's ROM read.
    wire signed [5:0] current_disparity=lookup_valid ?
        disparity+$signed(lookup_data[15:10]) : 6'sd0;
    wire [1:0] disparity_class=current_disparity==0 ? 2'd0 :
        current_disparity[5] ? 2'd2 : 2'd1;
    always @* begin
        case(mode)
            3'd1:lookup_address={disparity_class,video_data};
            3'd2:lookup_address={2'd3,CHANNEL_INDEX,2'd1,4'd0};
            3'd3:lookup_address={2'd3,CHANNEL_INDEX,2'd2,data_island_data};
            3'd4:lookup_address={2'd3,CHANNEL_INDEX,2'd3,2'd0,control_data};
            default:lookup_address={2'd3,CHANNEL_INDEX,2'd0,2'd0,control_data};
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin disparity<=0;lookup_valid<=0;end
        else begin
            lookup_valid<=1;
            if(mode==3'd1) disparity<=current_disparity;
            else disparity<=0;
        end
    end
    // Reset has the original asynchronous output and release behavior. BRAM
    // payloads themselves need no reset and are valid after the first read.
    assign symbol=lookup_valid ? lookup_data[9:0] : 10'b1101010100;
endmodule
