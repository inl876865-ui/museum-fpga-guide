`timescale 1ns/1ps
// Stationary, playback-counter-driven frame snapshots. The index RAM has one-cycle latency.
module caption_scheduler #(
    parameter integer FRAME_BUDGET_CYCLES=28000
)(
    input wire clk,rst,frame_start,enabled,menu_open,playback_active,
    input wire [31:0] audio_session,played_samples,
    input wire header_valid,header_timed,
    input wire [31:0] header_session,cycle_samples,
    input wire [6:0] cue_count,
    output reg [8:0] index_address,
    input wire [31:0] index_data,
    input wire bank0_valid,bank1_valid,
    input wire [31:0] bank0_session,bank1_session,
    input wire [5:0] bank0_cue,bank1_cue,
    output reg release_bank0,release_bank1,
    output wire [31:0] release_session0,release_session1,
    output reg [6:0] wanted_cue,
    output wire wanted_valid,
    output reg frame_visible,frame_bank,
    output reg [9:0] frame_width,
    output reg [2:0] frame_color_id,
    output reg signed [11:0] frame_text_x,
    output reg [14:0] calculation_cycles
);
    localparam IDLE=0,NORMALIZE=1,ADDRESS=2,WAIT_RAM=3,LATCH=4,APPLY=6;
    reg [2:0] state;
    reg [31:0] working_session,position,cue_start;
    reg [9:0] cue_width;
    reg [5:0] scan_cue;
    reg [2:0] word_index;
    reg selection_active,decision_valid;
    assign wanted_valid=decision_valid;
    // Cue selection keeps full sample precision; horizontal motion is removed.
    wire [31:0] subtract_operand=state==NORMALIZE && !header_timed ? cycle_samples :
                                 state==LATCH && word_index==1 ? index_data : cue_start;
    wire [32:0] position_difference={1'b0,position}-{1'b0,subtract_operand};
    wire context_valid=enabled && playback_active && header_valid &&
                       header_session==audio_session && cue_count!=0 && cue_count<=64;
    wire have_bank0=bank0_valid && bank0_session==audio_session && bank0_cue==wanted_cue;
    wire have_bank1=bank1_valid && bank1_session==audio_session && bank1_cue==wanted_cue;
    wire [6:0] following_cue=wanted_cue+1'b1<cue_count ? wanted_cue+1'b1 :
                              header_timed ? 7'd64 : 7'd0;
    wire keep0=wanted_cue<64 && (bank0_cue==wanted_cue || bank0_cue==following_cue);
    wire keep1=wanted_cue<64 && (bank1_cue==wanted_cue || bank1_cue==following_cue);
    assign release_session0=bank0_session;
    assign release_session1=bank1_session;
    // Retain both buffers while a new frame's desired cue is still being found.
    always @(posedge clk or posedge rst) begin
        if(rst) begin release_bank0<=0;release_bank1<=0;end
        else begin
            release_bank0<=bank0_valid && (bank0_session!=audio_session || !context_valid ||
                          (decision_valid && state==IDLE && !keep0));
            release_bank1<=bank1_valid && (bank1_session!=audio_session || !context_valid ||
                          (decision_valid && state==IDLE && !keep1));
        end
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=IDLE;working_session<=0;position<=0;cue_start<=0;
            cue_width<=0;scan_cue<=0;word_index<=0;selection_active<=0;decision_valid<=0;
            index_address<=0;
            wanted_cue<=64;frame_visible<=0;frame_bank<=0;frame_width<=0;frame_text_x<=112;frame_color_id<=0;
            calculation_cycles<=0;
        end else begin
            if(!context_valid || working_session!=audio_session) begin
                working_session<=audio_session;state<=IDLE;wanted_cue<=64;frame_visible<=0;
                decision_valid<=0;calculation_cycles<=0;frame_color_id<=0;
            end else if(frame_start) begin
                // Restart from an absolute audio snapshot; a late previous result cannot leak.
                position<=played_samples;state<=NORMALIZE;scan_cue<=0;word_index<=0;
                calculation_cycles<=0;
            end else if(state!=IDLE && calculation_cycles>=FRAME_BUDGET_CYCLES-1) begin
                state<=IDLE;frame_visible<=0;wanted_cue<=64;decision_valid<=1;
            end else begin
                if(state!=IDLE) calculation_cycles<=calculation_cycles+1'b1;
                case(state)
                    IDLE: begin end
                    NORMALIZE: begin
                        if(!header_timed && cycle_samples<32'd940800) begin
                            wanted_cue<=64;frame_visible<=0;decision_valid<=1;state<=IDLE;
                        end else if(!header_timed && !position_difference[32])
                            position<=position_difference[31:0];
                        else state<=ADDRESS;
                    end
                    ADDRESS: begin index_address<={scan_cue,word_index};state<=WAIT_RAM;end
                    WAIT_RAM: state<=LATCH;
                    LATCH: begin
                        // Reject an expired cue as soon as its end is read. Only
                        // width is needed for the selected cue.
                        case(word_index)
                            0:begin cue_start<=index_data;word_index<=1;state<=ADDRESS;end
                            1:begin
                                if(position_difference[32]) begin
                                    wanted_cue<={1'b0,scan_cue};word_index<=2;state<=ADDRESS;
                                end else if({1'b0,scan_cue}+1'b1>=cue_count) begin
                                    wanted_cue<=64;frame_visible<=0;decision_valid<=1;state<=IDLE;
                                end else begin scan_cue<=scan_cue+1'b1;word_index<=0;state<=ADDRESS;end
                            end
                            // Read the already-validated word7 through the existing index RAM.
                            // Legacy v1 stores zero, selecting the original ink.
                            2:begin cue_width<=index_data[9:0];selection_active<=!position_difference[32];word_index<=7;state<=ADDRESS;end
                            7:state<=APPLY;
                            default:state<=IDLE;
                        endcase
                    end
                    APPLY: begin
                        frame_width<=cue_width;
                        frame_color_id<=index_data[2:0];
                        frame_bank<=!have_bank0 && have_bank1;
                        frame_visible<=selection_active && (have_bank0 || have_bank1) && !menu_open;
                        // CAP keeps24px cells; the display uses16px cells.
                        // row_bytes=3*characters,so this7-bit divide centers16*n.
                        frame_text_x<=12'sd320-$signed({2'b00,(cue_width[9:3]/7'd3),3'b000});
                        decision_valid<=1;state<=IDLE;
                    end
                    default: state<=IDLE;
                endcase
            end
        end
    end
endmodule
