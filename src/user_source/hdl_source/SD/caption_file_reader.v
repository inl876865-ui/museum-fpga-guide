`timescale 1ns/1ps
// SD-domain CAP client. PCM start/ready is never gated by this client.
module caption_file_reader #(
    parameter integer SD_TIMEOUT_CYCLES=40000000
)(
    input wire clk,rst,pixel_clk,
    input wire scan_reset,scan_done,found_valid,
    input wire [63:0] found_name,
    input wire [31:0] found_cluster,found_size,
    input wire request_active,wanted_valid,
    input wire [31:0] request_session,request_pcm_bytes,
    input wire [3:0] request_tag,
    input wire [6:0] wanted_cue,
    input wire [63:0] audio_name,
    input wire audio_name_valid,
    input wire [3:0] audio_tag,
    input wire [31:0] audio_size,
    input wire sd_initialized,sd_owned,sd_valid,sd_done,
    input wire [7:0] sd_byte,sectors_per_cluster,
    input wire [31:0] fat_lba,data_lba,max_cluster,
    output wire sd_request,
    output wire [31:0] sd_address,
    output reg transport_recover,
    input wire free0,free1,cached0,cached1,
    input wire [31:0] cache_session0,cache_session1,
    input wire [5:0] cache_cue0,cache_cue1,
    output wire bank_reserve,bank_write,bank_publish,bank_discard,bank_abort,bank_select,
    output wire [11:0] bank_address,
    output wire [7:0] bank_data,
    output wire [5:0] publish_cue,
    output wire [31:0] publish_session,
    output wire header_valid,header_timed,
    output wire [31:0] header_session,cycle_samples,
    output wire [6:0] cue_count,
    input wire [8:0] pixel_index_address,
    output wire [31:0] pixel_index_data,
    output reg [3:0] status
);
    localparam IDLE=0,QUERY=1,RESET_STREAM=2,STREAM=3,COMPLETE=4,CANCEL=5,FAILED=6,ARM=7;
    reg [2:0] state;
    reg [2:0] quiet_count;
    reg lookup_start,stream_start,parser_start,reuse_next,restarting,fail_after_cancel;
    reg [63:0] job_name;
    reg [31:0] job_session,job_pcm_bytes,file_cluster;
    reg [17:0] file_size;
    reg [3:0] job_tag;
    wire catalog_ready,catalog_done,catalog_found,catalog_overflow;
    wire [31:0] catalog_cluster,catalog_size;
    wire [1:0] catalog_error;
    caption_catalog #(.INPUTS_HELD(1)) u_catalog(.clk(clk),.rst(rst),.scan_reset(scan_reset),.scan_done(scan_done),
        .found_valid(found_valid),.found_name(found_name),.found_cluster(found_cluster),.found_size(found_size),
        .query_start(lookup_start),.query_name(job_name),.ready(catalog_ready),.query_done(catalog_done),
        .query_found(catalog_found),.query_cluster(catalog_cluster),.query_size(catalog_size),
        .query_error(catalog_error),.overflow(catalog_overflow));
    wire identity_ready=audio_name_valid && audio_tag==request_tag && audio_size==request_pcm_bytes;
    wire same_request=request_active && identity_ready && request_session==job_session && request_tag==job_tag &&
                      request_pcm_bytes==job_pcm_bytes && audio_name==job_name;
    wire client_reset=rst || state==IDLE || state==QUERY || state==RESET_STREAM || state==FAILED;
    wire file_busy,file_done,file_valid;
    wire [7:0] file_byte,file_error;
    wire [31:0] file_offset,sector_lba;
    wire sector_request,sector_busy,sector_done,sector_valid;
    wire [7:0] sector_byte,sector_error;
    wire [8:0] sector_index;
    wire data_allow,buffer_valid,buffer_end,buffer_overflow,parser_ready;
    wire [7:0] buffer_byte,buffer_error;
    wire p_header,p_timed,p_complete,p_failed;
    wire [3:0] p_error;
    wire [31:0] p_session,p_cycle;
    wire [6:0] p_count;
    wire wanted_bad,next_bad,bad_queries_ready;
    wire p_reserve,p_write,p_publish,p_discard;
    wire [5:0] stream_cue;
    wire parser_waiting;
    wire c0=cached0 && cache_session0==job_session;
    wire c1=cached1 && cache_session1==job_session;
    wire [6:0] next_cue=wanted_cue+1'b1<p_count ? wanted_cue+1'b1 : p_timed ? 7'd64 : 7'd0;
    wire have_current=(c0 && cache_cue0==wanted_cue) || (c1 && cache_cue1==wanted_cue) || wanted_bad;
    wire have_next=next_cue==64 || (c0 && cache_cue0==next_cue) || (c1 && cache_cue1==next_cue) || next_bad;
    wire [6:0] missing_cue=!have_current ? wanted_cue : next_cue;
    wire need_earlier=bad_queries_ready && wanted_valid && wanted_cue<64 && (!have_current || !have_next) &&
                      (p_complete || (parser_waiting && missing_cue<{1'b0,stream_cue}));
    assign publish_session=job_session;
    assign bank_reserve=p_reserve && state==STREAM && same_request;
    assign bank_write=p_write && state==STREAM && same_request;
    assign bank_publish=p_publish && state==STREAM && same_request && !p_failed;
    assign bank_discard=p_discard && state==STREAM;
    assign bank_abort=state!=STREAM || !same_request || p_failed || buffer_overflow;
    assign header_valid=p_header && !p_failed && same_request &&
                        (state==STREAM || state==COMPLETE || restarting && (state==CANCEL || state==RESET_STREAM || state==ARM));
    assign header_session=p_session;assign header_timed=p_timed;assign cycle_samples=p_cycle;assign cue_count=p_count;
    caption_file_streamer #(.FILE_SIZE_BITS(18),.MAX_VISITED_CLUSTERS(512)) u_streamer (
        .clk(clk),.rst_n(!client_reset),.file_start(stream_start),
        .data_sector_allow(data_allow && state==STREAM && same_request),
        .first_cluster(file_cluster),.file_size({14'd0,file_size}),.sectors_per_cluster(sectors_per_cluster),
        .fat_start_lba(fat_lba),.data_start_lba(data_lba),.max_cluster(max_cluster),
        .file_busy(file_busy),.file_done(file_done),.file_valid(file_valid),.file_byte(file_byte),
        .file_byte_offset(file_offset),.fs_error(file_error),.sector_req(sector_request),.sector_lba(sector_lba),
        .sector_busy(sector_busy),.sector_valid(sector_valid),.sector_byte(sector_byte),.sector_byte_index(sector_index),
        .sector_done(sector_done),.sector_error(sector_error));
    sd_sector_adapter #(.TIMEOUT_CYCLES(SD_TIMEOUT_CYCLES)) u_adapter (
        .clk(clk),.rst_n(!client_reset),.abort(1'b0),.sd_init_done(sd_initialized),
        .sector_req(sector_request && state==STREAM && same_request),.sector_lba(sector_lba),
        .sector_busy(sector_busy),.sector_done(sector_done),.sector_valid(sector_valid),
        .sector_byte(sector_byte),.sector_byte_index(sector_index),.sector_error(sector_error),
        .sd_sec_read(sd_request),.sd_sec_read_addr(sd_address),
        .sd_sec_read_data_valid(sd_valid && sd_owned),.sd_sec_read_end(sd_done && sd_owned),.sd_sec_read_data(sd_byte));
    caption_sector_buffer u_sector_buffer(.clk(clk),.rst(rst),.start(client_reset || parser_start),
        .file_valid(file_valid),.file_byte(file_byte),.file_done(file_done),.file_error(file_error),
        .data_sector_allow(data_allow),.byte_valid(buffer_valid),.byte_data(buffer_byte),.byte_ready(parser_ready),
        .end_valid(buffer_end),.end_error(buffer_error),.overflow(buffer_overflow));
    caption_cap_parser #(.ENABLE_CACHE_FEEDBACK(1),.BAD_CUES_RAM(1)) u_parser (
        .clk(clk),.rst(rst || scan_reset),.start(parser_start),.reuse_index(reuse_next),.pixel_clk(pixel_clk),
        .expected_file_size(file_size),.expected_name(job_name),.expected_pcm_bytes(job_pcm_bytes),.request_session(job_session),
        .byte_valid(buffer_valid),.byte_data(buffer_byte),.byte_ready(parser_ready),.end_valid(buffer_end),.end_error(buffer_error),
        .wanted_valid(wanted_valid && same_request),.wanted_cue(wanted_cue),.bank0_free(free0),.bank1_free(free1),
        .cached0(c0),.cached1(c1),.cached_cue0(cache_cue0),.cached_cue1(cache_cue1),
        .stream_cue(stream_cue),.waiting_for_demand(parser_waiting),
        .bank_reserve(p_reserve),.bank_write(p_write),.bank_publish(p_publish),.bank_discard(p_discard),
        .bank_select(bank_select),.bank_address(bank_address),.bank_data(bank_data),.publish_cue(publish_cue),
        .header_valid(p_header),.header_timed(p_timed),.file_complete(p_complete),.failed(p_failed),.error_code(p_error),
        .cue_count(p_count),.cycle_samples(p_cycle),.header_session(p_session),.bad_cues(),
        .wanted_bad(wanted_bad),.next_bad(next_bad),.bad_queries_ready(bad_queries_ready),
        .pixel_index_address(pixel_index_address),.pixel_index_data(pixel_index_data));
    reg owned_seen;
    always @(posedge clk or posedge rst) begin
        if(rst) begin owned_seen<=0;transport_recover<=0;end
        else begin
            transport_recover<=0;
            if(client_reset) owned_seen<=0;
            else begin
                if(sd_owned) owned_seen<=1;
                if(sector_done) begin
                    if(sector_error==2 && owned_seen) transport_recover<=1;
                    owned_seen<=0;
                end
            end
        end
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=IDLE;quiet_count<=0;lookup_start<=0;stream_start<=0;parser_start<=0;
            reuse_next<=0;restarting<=0;fail_after_cancel<=0;job_name<=0;job_session<=0;job_pcm_bytes<=0;
            file_cluster<=0;file_size<=0;job_tag<=0;status<=0;
        end else begin
            lookup_start<=0;stream_start<=0;parser_start<=0;
            if(scan_reset || ((state==STREAM || state==COMPLETE || state==RESET_STREAM || state==QUERY || state==ARM) &&
                (!same_request || !sd_initialized))) begin
                state<=CANCEL;quiet_count<=0;restarting<=0;fail_after_cancel<=0;
            end else case(state)
                IDLE: if(request_active && identity_ready && catalog_ready && sd_initialized) begin
                    job_name<=audio_name;job_session<=request_session;job_tag<=request_tag;job_pcm_bytes<=request_pcm_bytes;
                    lookup_start<=1;state<=QUERY;status<=0;restarting<=0;
                end
                QUERY: if(catalog_done) begin
                    if(!catalog_found || catalog_error!=0 || catalog_size<152 || catalog_size>149552) begin state<=FAILED;status<=7;end
                    else begin
                        reuse_next<=p_header && p_session==job_session && file_cluster==catalog_cluster && file_size==catalog_size;
                        file_cluster<=catalog_cluster;file_size<=catalog_size[17:0];quiet_count<=0;state<=RESET_STREAM;
                    end
                end
                RESET_STREAM: if(quiet_count==3) begin
                    parser_start<=1;stream_start<=1;state<=ARM;quiet_count<=0;
                end else quiet_count<=quiet_count+1'b1;
                ARM:state<=STREAM;
                STREAM: begin
                    if(p_failed || buffer_overflow) begin
                        status<=buffer_overflow ? 4'd6 : p_error;state<=CANCEL;quiet_count<=0;restarting<=0;fail_after_cancel<=1;
                    end else if(need_earlier) begin
                        restarting<=1;fail_after_cancel<=0;quiet_count<=0;state<=CANCEL;
                    end else if(p_complete) state<=COMPLETE;
                end
                COMPLETE: if(need_earlier) begin restarting<=1;fail_after_cancel<=0;quiet_count<=0;state<=CANCEL;end
                CANCEL: begin
                    if(sector_busy || sd_owned) quiet_count<=0;
                    else if(quiet_count==3) begin
                        quiet_count<=0;
                        if(restarting && same_request && !fail_after_cancel) begin reuse_next<=1;state<=RESET_STREAM;end
                        else begin state<=fail_after_cancel && same_request ? FAILED : IDLE;restarting<=0;end
                    end else quiet_count<=quiet_count+1'b1;
                end
                FAILED: if(!request_active || request_session!=job_session || request_tag!=job_tag) state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
