`timescale 1ns/1ps
// Course sector interface, with bounded wait and exact sector length checks.
module sd_sector_adapter #(
    parameter integer TIMEOUT_CYCLES=50000000
)(
    input wire clk,rst_n,abort,sd_init_done,
    input wire sector_req,
    input wire [31:0] sector_lba,
    output reg sector_busy,sector_done,
    output reg sector_valid,
    output reg [7:0] sector_byte,
    output reg [8:0] sector_byte_index,
    output reg [7:0] sector_error,
    output reg sd_sec_read,
    output reg [31:0] sd_sec_read_addr,
    input wire sd_sec_read_data_valid,sd_sec_read_end,
    input wire [7:0] sd_sec_read_data
);
    // The terminal busy clock increments timer through TIMEOUT_CYCLES.
    // Keep 32 bits for nonpositive/signed-overflow boundary parameters.
    localparam integer TIMER_WIDTH=(TIMEOUT_CYCLES>0 && TIMEOUT_CYCLES<32'h7fffffff) ?
        (TIMEOUT_CYCLES==1 ? 1 : $clog2(TIMEOUT_CYCLES+1)) : 32;
    reg [TIMER_WIDTH-1:0] timer;
    reg [10:0] count;
    reg done_pending,timeout_reached;
    wire [11:0] final_count={1'b0,count}+(sd_sec_read_data_valid?12'd1:12'd0);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sector_busy<=0;sector_done<=0;sector_error<=0;sd_sec_read<=0;
            sd_sec_read_addr<=0;timer<=0;count<=0;timeout_reached<=0;
            sector_valid<=0;sector_byte<=0;sector_byte_index<=0;done_pending<=0;
        end else begin
            // Register the byte bundle before directory/streamer decoding.
            // Completion follows the last registered byte by one clock.
            sector_valid<=sector_busy && !abort && sd_sec_read_data_valid && count<512;
            sector_byte<=sd_sec_read_data;sector_byte_index<=count[8:0];
            sector_done<=done_pending;done_pending<=0;
            if(abort) begin sector_done<=0;done_pending<=0;sector_valid<=0;sector_busy<=0;sd_sec_read<=0;timer<=0;count<=0;timeout_reached<=0;end
            else if(!sector_busy) begin
                if(sector_req && sd_init_done) begin
                    sector_busy<=1;sd_sec_read<=1;sd_sec_read_addr<=sector_lba;
                    timer<=0;count<=0;sector_error<=0;timeout_reached<=TIMEOUT_CYCLES==1;
                end
            end else begin
                timer<=timer+1'b1;
                // Predict the next timer comparison; timeout still occurs on the same clock.
                timeout_reached<=timer>=TIMEOUT_CYCLES-2;
                if(sd_sec_read_data_valid && count<1024) count<=count+1'b1;
                if(!sd_init_done || timeout_reached) begin
                    sector_error<=2;done_pending<=1;sector_busy<=0;sd_sec_read<=0;
                end else if(sd_sec_read_end) begin
                    sector_error<=final_count==512?0:3;
                    done_pending<=1;sector_busy<=0;sd_sec_read<=0;
                end
            end
        end
    end
endmodule
