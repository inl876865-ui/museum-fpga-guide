`timescale 1ns/1ps
// 32 CAP entries in one 128x32 RAM. Lookup compares two exact filename words.
module caption_catalog #(
    // The CAP scanner holds found_* until its next directory event (>=32 clocks).
    // The reader holds query_name until query_done, including cancellation.
    parameter integer INPUTS_HELD=0
) (
    input wire clk,rst,scan_reset,scan_done,
    input wire found_valid,
    input wire [63:0] found_name,
    input wire [31:0] found_cluster,found_size,
    input wire query_start,
    input wire [63:0] query_name,
    output wire ready,
    output reg query_done,query_found,
    output reg [31:0] query_cluster,query_size,
    output reg [1:0] query_error,
    output reg overflow
);
    (* ram_style="bram" *) reg [31:0] records[0:127];
    reg [5:0] count;
    reg writing;
    reg [4:0] write_slot;
    reg [1:0] write_word;
    reg [63:0] write_name;
    reg [31:0] write_cluster,write_size;
    wire [63:0] store_name=INPUTS_HELD!=0 ? found_name : write_name;
    wire [31:0] store_cluster=INPUTS_HELD!=0 ? found_cluster : write_cluster;
    wire [31:0] store_size=INPUTS_HELD!=0 ? found_size : write_size;
    reg [31:0] read_data;
    always @(posedge clk) begin
        if(writing) case(write_word)
            0:records[{write_slot,write_word}]<=store_name[63:32];
            1:records[{write_slot,write_word}]<=store_name[31:0];
            2:records[{write_slot,write_word}]<=store_cluster;
            3:records[{write_slot,write_word}]<=store_size;
        endcase
        else read_data<=records[{slot,word_index}];
    end
    localparam IDLE=0,ADDRESS=1,WAIT_RAM=2,LATCH=3,NEXT=4;
    reg [2:0] state;
    reg [4:0] slot;
    reg [1:0] word_index;
    reg [63:0] target;
    wire [63:0] compare_name=INPUTS_HELD!=0 ? query_name : target;
    reg [1:0] match_count;
    assign ready=scan_done && !writing && state==IDLE;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            count<=0;writing<=0;write_slot<=0;write_word<=0;write_name<=0;write_cluster<=0;write_size<=0;
            state<=IDLE;slot<=0;word_index<=0;
            target<=0;match_count<=0;
            overflow<=0;query_done<=0;query_found<=0;query_cluster<=0;query_size<=0;query_error<=0;
        end else begin
            query_done<=0;
            if(scan_reset) begin
                count<=0;writing<=0;overflow<=0;state<=IDLE;query_found<=0;query_error<=0;
            end else begin
                if(writing) begin
                    if(write_word==3) writing<=0;else write_word<=write_word+1'b1;
                end
                if(found_valid && !overflow) begin
                    if(writing || count==32) overflow<=1;
                    else begin
                        write_slot<=count[4:0];count<=count+1'b1;write_word<=0;writing<=1;
                        if(INPUTS_HELD==0) begin write_name<=found_name;write_cluster<=found_cluster;write_size<=found_size;end
                    end
                end
                case(state)
                    IDLE: if(query_start && scan_done && !writing) begin
                        query_found<=0;query_cluster<=0;query_size<=0;query_error<=0;match_count<=0;
                        if(overflow) begin query_done<=1;query_error<=1;end
                        else if(count==0) query_done<=1;
                        else begin if(INPUTS_HELD==0)target<=query_name;slot<=0;word_index<=0;state<=ADDRESS;end
                    end
                    ADDRESS: state<=WAIT_RAM;
                    WAIT_RAM: state<=LATCH;
                    LATCH: begin
                        case(word_index)
                            0: begin
                                if(read_data==compare_name[63:32]) begin word_index<=1;state<=ADDRESS;end
                                else state<=NEXT;
                            end
                            1: begin
                                if(read_data==compare_name[31:0]) begin word_index<=2;state<=ADDRESS;end
                                else state<=NEXT;
                            end
                            2: begin query_cluster<=read_data;word_index<=3;state<=ADDRESS;end
                            3: begin
                                if(match_count!=2) match_count<=match_count+1'b1;
                                query_size<=read_data;state<=NEXT;
                            end
                        endcase
                    end
                    NEXT: if({1'b0,slot}+1'b1>=count) begin
                        query_done<=1;query_found<=match_count==1;query_error<=match_count>1 ? 2'd2 : 2'd0;state<=IDLE;
                    end else begin slot<=slot+1'b1;word_index<=0;state<=ADDRESS;end
                    default:state<=IDLE;
                endcase
            end
        end
    end
endmodule
