`timescale 1ns/1ps
// A dedicated TRANS.PCM stream; the narration catalog and pointers are separate.
module transition_cue_player #(
    parameter integer CLK_HZ=100000000,
    parameter integer RESTART_ON_TRIGGER=1
) (
    input wire clk,rst,pixel_clk,pixel_rst,trigger,sample_tick,sample_ready,
    input wire scan_reset,found_valid,
    input wire [31:0] found_cluster,found_size,
    input wire [7:0] sectors_per_cluster,
    input wire [31:0] fat_start_lba,data_start_lba,max_cluster,
    output wire signed [15:0] sample_data,
    output wire sample_valid,
    output wire sd_request,
    output wire [31:0] sd_address,
    input wire sd_initialized,sd_byte_valid,sd_done,sd_owned,
    input wire [7:0] sd_byte
);
    reg event_toggle;
    always @(posedge pixel_clk or posedge pixel_rst) begin
        if(pixel_rst) event_toggle<=0;
        else if(trigger) event_toggle<=~event_toggle;
    end
    reg [1:0] event_sync,end_sync,reset_sync;
    reg event_seen,pending,have_file;
    reg [31:0] cluster,file_max_cluster;
    reg [17:0] size;
    reg [2:0] state;
    reg [3:0] reset_count;
    localparam IDLE=0,RESET=1,START=2,RUN=3,STOP=4;
    wire stream_reset=state==RESET || state==IDLE;
    wire file_reset=stream_reset || state==STOP;
    wire file_start=state==START;
    wire allow,file_busy,file_done,file_valid,ended,active,error;
    wire [7:0] file_byte,fs_error,sector_byte,sector_error;
    wire [31:0] file_offset,sector_lba;
    wire sector_request,sector_busy,sector_done,sector_valid;
    wire [8:0] sector_index;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            event_sync<=0;end_sync<=0;event_seen<=0;pending<=0;have_file<=0;
            cluster<=0;file_max_cluster<=0;size<=0;state<=IDLE;reset_count<=0;
        end else begin
            event_sync<={event_sync[0],event_toggle};end_sync<={end_sync[0],ended};
            // Volume layout is published after directory entries; latch at playback startup.
            if(state==RESET) file_max_cluster<=max_cluster;
            if(scan_reset) begin have_file<=0;pending<=0;end
            if(found_valid) begin have_file<=found_size<262144;cluster<=found_cluster;size<=found_size[17:0];end
            if(event_sync[1]!=event_seen) begin event_seen<=event_sync[1];pending<=have_file;end
            case(state)
                IDLE: if(pending && have_file && !scan_reset && sd_initialized) begin
                    pending<=0;reset_count<=0;state<=RESET;
                end
                RESET: if(reset_count==15) state<=START;
                       else reset_count<=reset_count+1'b1;
                START: state<=RUN;
                RUN: if(RESTART_ON_TRIGGER!=0 && pending) state<=STOP;
                     else if(end_sync[1] && !file_busy && !sector_busy && !sd_owned) state<=IDLE;
                STOP: if(!sector_busy && !sd_owned) begin
                    pending<=0;reset_count<=0;state<=have_file ? RESET : IDLE;
                end
            endcase
        end
    end
    always @(posedge pixel_clk or posedge pixel_rst) begin
        if(pixel_rst) reset_sync<=3;
        else reset_sync<={reset_sync[0],file_reset};
    end
    fat32_file_streamer #(.FILE_SIZE_BITS(18),.MAX_VISITED_CLUSTERS(512)) file_stream (
        .clk(clk),.rst_n(!rst && !file_reset),.file_start(file_start),
        .data_sector_allow(allow && state==RUN),.first_cluster(cluster),.file_size(size),
        .sectors_per_cluster(sectors_per_cluster),.fat_start_lba(fat_start_lba),
        .data_start_lba(data_start_lba),.max_cluster(file_max_cluster),
        .file_busy(file_busy),.file_done(file_done),.file_valid(file_valid),
        .file_byte(file_byte),.file_byte_offset(file_offset),.fs_error(fs_error),
        .sector_req(sector_request),.sector_lba(sector_lba),.sector_busy(sector_busy),
        .sector_valid(sector_valid),.sector_byte(sector_byte),.sector_byte_index(sector_index),
        .sector_done(sector_done),.sector_error(sector_error));
    pcm_file_fifo #(.ADDR_WIDTH(9)) sample_fifo (
        .wr_clk(clk),.wr_rst_n(!rst && !file_reset),.file_valid(file_valid),.file_byte(file_byte),
        .file_done(file_done),.file_error(fs_error),.sector_allow(allow),
        .rd_clk(pixel_clk),.rd_rst_n(!pixel_rst && !reset_sync[1]),
        .sample_tick(sample_tick),.sample_ready(sample_ready),.sample_out(sample_data),
        .sample_valid(sample_valid),.stream_active(active),.stream_end(ended),.stream_error(error),
        .sample_started(),.played_samples());
    sd_sector_adapter #(.TIMEOUT_CYCLES(CLK_HZ/2)) adapter (
        .clk(clk),.rst_n(!rst && !stream_reset),.abort(1'b0),.sd_init_done(sd_initialized),
        .sector_req(sector_request),.sector_lba(sector_lba),.sector_busy(sector_busy),
        .sector_done(sector_done),.sector_valid(sector_valid),.sector_byte(sector_byte),
        .sector_byte_index(sector_index),.sector_error(sector_error),
        .sd_sec_read(sd_request),.sd_sec_read_addr(sd_address),
        .sd_sec_read_data_valid(sd_byte_valid && sd_owned),
        .sd_sec_read_end(sd_done && sd_owned),.sd_sec_read_data(sd_byte));
endmodule
