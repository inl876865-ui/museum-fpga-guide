`timescale 1ns/1ps
// Observe real audio sessions; bridge the CAP reader and immutable bitmap banks.
module caption_engine #(parameter integer SD_TIMEOUT_CYCLES=40000000)(
    input wire clk,rst,pixel_clk,pixel_rst,frame_start,
    input wire enabled,menu_open,source_wav,stream_reset_pixel,sample_started,audio_end,
    input wire [3:0] pixel_file_tag,audio_file_tag,
    input wire [31:0] pixel_file_size,audio_file_size,played_samples,
    input wire [63:0] audio_name,
    input wire audio_name_valid,
    input wire scan_reset,scan_done,found_valid,
    input wire [63:0] found_name,
    input wire [31:0] found_cluster,found_size,
    input wire sd_initialized,sd_owned,sd_valid,sd_done,
    input wire [7:0] sd_byte,sectors_per_cluster,
    input wire [31:0] fat_lba,data_lba,max_cluster,
    output wire sd_request,transport_recover,
    output wire [31:0] sd_address,
    input wire [11:0] bitmap_address,
    input wire bitmap_read_bank,
    output wire [7:0] bitmap_byte,
    output wire frame_visible,frame_bank,
    output wire [9:0] frame_width,
    output wire [2:0] frame_color_id,
    output wire signed [11:0] frame_text_x,
    output wire [3:0] status,
    output wire ownership_error
);
    reg [31:0] audio_session;
    reg first_seen;
    always @(posedge pixel_clk or posedge pixel_rst) begin
        if(pixel_rst) begin audio_session<=0;first_seen<=0;end
        else if(stream_reset_pixel || audio_end) first_seen<=0;
        else if(sample_started) begin audio_session<=audio_session+1'b1;first_seen<=1;end
    end
    wire active=first_seen && source_wav && !stream_reset_pixel && !audio_end;
    wire [6:0] wanted;
    wire wanted_valid;
    wire [76:0] request_sd;
    player_settings_cdc #(.WIDTH(77),.RESET_VALUE(77'd0)) request_bundle(
        .src_clk(pixel_clk),.src_rst(pixel_rst),
        .src_value({audio_session,pixel_file_tag,pixel_file_size,active && enabled,wanted_valid,wanted}),
        .dst_clk(clk),.dst_rst(rst),.dst_value(request_sd));
    wire reader_header,reader_timed;
    wire [31:0] reader_session,reader_cycle,publish_session;
    wire [6:0] reader_count;
    wire [72:0] header_pixel;
    player_settings_cdc #(.WIDTH(73),.RESET_VALUE(73'd0)) header_bundle(
        .src_clk(clk),.src_rst(rst),.src_value({reader_header,reader_session,reader_timed,reader_count,reader_cycle}),
        .dst_clk(pixel_clk),.dst_rst(pixel_rst),.dst_value(header_pixel));
    wire free0,free1,valid0,valid1,release0,release1;
    wire [31:0] sid0,sid1,release_sid0,release_sid1;
    wire [5:0] cue0,cue1;
    wire reserve,write,publish,discard,abort_write,write_bank;
    wire [11:0] write_address;
    wire [7:0] write_data;
    wire [5:0] publish_cue;
    wire cached0,cached1;
    wire [31:0] cached_sid0,cached_sid1;
    wire [5:0] cached_cue0,cached_cue1;
    wire [8:0] index_address;
    wire [31:0] index_data;
    caption_buffers u_buffers(.write_clk(clk),.write_rst(rst),.pixel_clk(pixel_clk),.pixel_rst(pixel_rst),
        .publish_session(publish_session),.reserve(reserve),.write(write),.publish(publish),.discard(discard),
        .abort_write(abort_write),.write_bank(write_bank),.write_address(write_address),.write_data(write_data),.publish_cue(publish_cue),
        .release0(release0),.release1(release1),.release_session0(release_sid0),.release_session1(release_sid1),
        .free0(free0),.free1(free1),.valid0(valid0),.valid1(valid1),.session0(sid0),.session1(sid1),.cue0(cue0),.cue1(cue1),
        .pixel_address(bitmap_address),.pixel_bank(bitmap_read_bank),.pixel_byte(bitmap_byte),.ownership_error(ownership_error),
        .any_reserved(),.source_cached0(cached0),.source_cached1(cached1),.source_id0(cached_sid0),.source_id1(cached_sid1),
        .source_index0(cached_cue0),.source_index1(cached_cue1));
    caption_scheduler u_scheduler(.clk(pixel_clk),.rst(pixel_rst),.frame_start(frame_start),.enabled(enabled),.menu_open(menu_open),
        .playback_active(active),.audio_session(audio_session),.played_samples(played_samples),
        .header_valid(header_pixel[72]),.header_session(header_pixel[71:40]),.header_timed(header_pixel[39]),
        .cue_count(header_pixel[38:32]),.cycle_samples(header_pixel[31:0]),.index_address(index_address),.index_data(index_data),
        .bank0_valid(valid0),.bank1_valid(valid1),.bank0_session(sid0),.bank1_session(sid1),.bank0_cue(cue0),.bank1_cue(cue1),
        .release_bank0(release0),.release_bank1(release1),.release_session0(release_sid0),.release_session1(release_sid1),
        .wanted_cue(wanted),.wanted_valid(wanted_valid),.frame_visible(frame_visible),.frame_bank(frame_bank),
        .frame_width(frame_width),.frame_text_x(frame_text_x),.frame_color_id(frame_color_id),.calculation_cycles());
    caption_file_reader #(.SD_TIMEOUT_CYCLES(SD_TIMEOUT_CYCLES)) u_reader(
        .clk(clk),.rst(rst),.pixel_clk(pixel_clk),.scan_reset(scan_reset),.scan_done(scan_done),.found_valid(found_valid),
        .found_name(found_name),.found_cluster(found_cluster),.found_size(found_size),
        .request_session(request_sd[76:45]),.request_tag(request_sd[44:41]),.request_pcm_bytes(request_sd[40:9]),
        .request_active(request_sd[8]),.wanted_valid(request_sd[7]),.wanted_cue(request_sd[6:0]),
        .audio_name(audio_name),.audio_name_valid(audio_name_valid),.audio_tag(audio_file_tag),.audio_size(audio_file_size),
        .sd_initialized(sd_initialized),.sd_owned(sd_owned),.sd_valid(sd_valid),.sd_byte(sd_byte),.sd_done(sd_done),
        .sectors_per_cluster(sectors_per_cluster),.fat_lba(fat_lba),.data_lba(data_lba),.max_cluster(max_cluster),
        .sd_request(sd_request),.sd_address(sd_address),.transport_recover(transport_recover),
        .free0(free0),.free1(free1),.cached0(cached0),.cached1(cached1),.cache_session0(cached_sid0),.cache_session1(cached_sid1),
        .cache_cue0(cached_cue0),.cache_cue1(cached_cue1),.bank_reserve(reserve),.bank_write(write),.bank_publish(publish),
        .bank_discard(discard),.bank_abort(abort_write),.bank_select(write_bank),.bank_address(write_address),.bank_data(write_data),
        .publish_cue(publish_cue),.publish_session(publish_session),.header_valid(reader_header),.header_timed(reader_timed),
        .header_session(reader_session),.cycle_samples(reader_cycle),.cue_count(reader_count),
        .pixel_index_address(index_address),.pixel_index_data(index_data),.status(status));
endmodule
