`timescale 1ns/1ps
// Course scanner + streamer + sector adapter behind the existing player contract.
// Catalog outputs are first-cluster/size pairs, never physical start sectors.
module fat32_bmp_reader #(
    parameter integer CLK_FREQ_HZ=100000000,
    parameter integer SD_READ_TIMEOUT_MS=500,
    parameter integer MAX_IMAGES=4,
    parameter integer ENABLE_CAPTION=0,
    parameter integer ENABLE_ADAPTIVE_SCALING=0,
    parameter integer IMAGE_BITS=$clog2(MAX_IMAGES),
    parameter integer ENABLE_SHARED_SCALING_RAM=0
)(
    input wire clk,rst,load_abort,sd_init_done,
    input wire scale_clk,scale_rst,
    input wire scan_start,load_start,
    input wire [31:0] load_cluster,load_file_size,
    input wire [15:0] bmp_width,bmp_height,
    input wire bmp_pixel_ready,
    output wire ready,
    output reg scan_done,scan_found_valid,
    output reg [31:0] scan_found_cluster,scan_found_size,
    output reg [IMAGE_BITS:0] scan_found_total,
    output wire caption_found_valid,
    output wire [63:0] caption_found_name,
    output wire [31:0] caption_found_cluster,caption_found_size,
    output wire audio_found_valid,
    output wire [87:0] audio_found_name,
    output wire [31:0] audio_found_cluster,audio_found_size,
    output wire [7:0] audio_sectors_per_cluster,
    output wire [31:0] audio_fat_start_lba,audio_data_start_lba,audio_max_cluster,
    output reg [2:0] bmp_error,
    output reg load_error,load_done,scan_error,scan_reject,sd_recover,
    output reg write_req,
    input wire write_req_ack,
    output wire sd_sec_read,
    output wire [31:0] sd_sec_read_addr,
    input wire [7:0] sd_sec_read_data,
    input wire sd_sec_read_data_valid,sd_sec_read_end,
    output wire bmp_data_wr_en,
    output wire [23:0] bmp_data,
    output wire [8:0] bmp_buffer_address,
    output wire bmp_buffer_write,
    output wire [7:0] bmp_buffer_write_data,
    input wire [7:0] bmp_buffer_read_data,
    input wire catalog_lookup_start,
    input wire [IMAGE_BITS-1:0] catalog_lookup_index,
    output reg catalog_lookup_busy,catalog_lookup_valid,catalog_lookup_missing,
    output wire [63:0] catalog_lookup_pair
);
    localparam IDLE=0,SCAN=1,EMIT=2,ACK=3,START=4,LOAD=5,READ_ENTRY=6,EMIT_ENTRY=7;
    localparam integer TIMEOUT=(CLK_FREQ_HZ/1000)*SD_READ_TIMEOUT_MS;
    reg [2:0] state;
    reg [IMAGE_BITS:0] emit_index;
    wire picture_found_valid;wire [4:0] picture_found_index;
    wire [31:0] picture_found_cluster,picture_found_size;
    reg [MAX_IMAGES-1:0] picture_valid;
    (* ram_style="bram" *) reg [7:0] picture_catalog[0:MAX_IMAGES*8-1];
    reg [63:0] picture_read;
    reg [IMAGE_BITS-1:0] catalog_search_slot,catalog_search_rank,catalog_search_target;
    reg catalog_publish;
    reg [IMAGE_BITS+2:0] catalog_address;
    reg [2:0] catalog_phase;
    reg [7:0] catalog_byte;
    reg catalog_write_busy,catalog_read_busy,catalog_read_primed,catalog_read_valid;
    wire [63:0] picture_found_pair={picture_found_cluster,picture_found_size};
    wire catalog_first_valid=picture_valid[catalog_search_slot];
    wire catalog_second_valid=catalog_search_slot<MAX_IMAGES-1 &&
        picture_valid[catalog_search_slot+1'b1];
    wire catalog_first_match=catalog_first_valid && catalog_search_target==0;
    wire catalog_second_match=catalog_second_valid &&
        catalog_search_target==(catalog_first_valid ? 1 : 0);
    wire [1:0] catalog_valid_count={catalog_first_valid && catalog_second_valid,
        catalog_first_valid ^ catalog_second_valid};
    wire catalog_write_start=MAX_IMAGES>4 && state==SCAN && picture_found_valid &&
        !picture_valid[picture_found_index];
    wire catalog_scan_read_start=MAX_IMAGES>4 && state==EMIT && emit_index<MAX_IMAGES &&
        picture_valid[emit_index[IMAGE_BITS-1:0]] && !catalog_write_busy && !catalog_read_busy;
    wire catalog_query_read_start=catalog_lookup_busy && !catalog_publish &&
        (catalog_first_match || catalog_second_match) && !catalog_write_busy && !catalog_read_busy;
    wire [IMAGE_BITS-1:0] catalog_read_index=catalog_query_read_start ?
        (catalog_first_match ? catalog_search_slot : catalog_search_slot+1'b1) :
        emit_index[IMAGE_BITS-1:0];
    assign catalog_lookup_pair=picture_read;
    // ACK counting stops before TIMEOUT. Use the same conservative T+1
    // bound as the sector client; exceptional signed parameters stay 32 bits.
    localparam integer WAIT_WIDTH=(TIMEOUT>0 && TIMEOUT<32'h7fffffff) ?
        (TIMEOUT==1 ? 1 : $clog2(TIMEOUT+1)) : 32;
    reg [WAIT_WIDTH-1:0] wait_count;
    reg [31:0] file_cluster,file_size;
    reg scanner_start,stream_start,abort_internal;
    wire modules_rst=rst || load_abort || abort_internal;
    wire scanning=state==SCAN;
    wire scanner_done,stream_done,stream_valid,decoder_complete;
    wire [7:0] scanner_error,stream_error,stream_byte;
    wire [31:0] stream_offset;
    wire [2:0] decoder_error;
    wire [3:0] resource_valid;
    wire [31:0] cluster0,cluster1,cluster2,cluster3,size0,size1,size2,size3;
    wire [7:0] spc;
    wire [31:0] fat_lba,data_lba,max_cluster;
    // Volume layout must survive stream-only recovery/reset.
    reg [7:0] spc_q;
    reg [31:0] fat_q,data_q,max_q;
    assign audio_sectors_per_cluster = spc_q;
    assign audio_fat_start_lba = fat_q;
    assign audio_data_start_lba = data_q;
    assign audio_max_cluster = max_q;
    wire scanner_req,stream_req,busy,sector_done,sector_valid;
    wire [31:0] scanner_lba,stream_lba;
    wire [8:0] byte_index;
    wire [7:0] byte_data,sector_error;
    wire pixel_valid;
    wire stream_sector_allow;
    assign ready=state==IDLE && sd_init_done;
    assign bmp_data_wr_en=pixel_valid && state==LOAD && !load_abort && decoder_error==0 &&
        (ENABLE_ADAPTIVE_SCALING==0 || bmp_pixel_ready);
    // The scanner holds a record for at least32 clocks; serialize its first copy.
    // Writes and reads have exclusive lifetimes and share the address/phase.
    always @(posedge clk) begin
        if(catalog_write_busy && !rst && !scanner_start && !load_abort && !abort_internal)
            picture_catalog[catalog_address]<=picture_found_pair>>(catalog_phase*8);
        catalog_byte<=picture_catalog[catalog_address];
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            catalog_address<=0;catalog_phase<=0;catalog_write_busy<=0;
            catalog_read_busy<=0;catalog_read_primed<=0;catalog_read_valid<=0;
        end else begin
            catalog_read_valid<=0;
            if(load_abort || abort_internal || scanner_start || (scan_start && state==IDLE)) begin
                catalog_write_busy<=0;catalog_read_busy<=0;catalog_read_primed<=0;
            end else if(catalog_write_busy) begin
                catalog_address<=catalog_address+1'b1;
                if(catalog_phase==7)catalog_write_busy<=0;
                else catalog_phase<=catalog_phase+1'b1;
            end else if(catalog_read_busy) begin
                catalog_address<=catalog_address+1'b1;
                if(!catalog_read_primed)catalog_read_primed<=1;
                else begin
                    picture_read<={catalog_byte,picture_read[63:8]};
                    catalog_phase<=catalog_phase+1'b1;
                    if(catalog_phase==7)begin catalog_read_busy<=0;catalog_read_valid<=1;end
                end
            end else if(catalog_write_start) begin
                catalog_address<={picture_found_index,3'd0};catalog_phase<=0;catalog_write_busy<=1;
            end else if(catalog_scan_read_start || catalog_query_read_start) begin
                catalog_address<={catalog_read_index,3'd0};catalog_phase<=0;
                catalog_read_busy<=1;catalog_read_primed<=0;
            end
        end
    end
    // Directory lifetime is the volume scan, independent of stream-only abort.
    // Count remaining valid ordinals, two slots per clock, before byte assembly.
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            catalog_lookup_busy<=0;catalog_lookup_valid<=0;catalog_lookup_missing<=0;
            catalog_search_slot<=0;catalog_search_rank<=0;catalog_search_target<=0;catalog_publish<=0;
        end else begin
            catalog_lookup_valid<=0;catalog_lookup_missing<=0;
            if(load_abort || abort_internal || scanner_start || scan_start) begin
                catalog_lookup_busy<=0;catalog_publish<=0;
            end else if(catalog_lookup_busy) begin
                if(catalog_publish) begin
                    if(catalog_read_valid)begin
                        catalog_lookup_busy<=0;catalog_lookup_valid<=1;catalog_publish<=0;
                    end
                end else if(catalog_query_read_start) begin
                    catalog_publish<=1;
                end else if(catalog_search_slot>=MAX_IMAGES-2) begin
                    catalog_lookup_busy<=0;catalog_lookup_missing<=1;
                end else begin
                    catalog_search_slot<=catalog_search_slot+2'd2;
                    catalog_search_target<=catalog_search_target-catalog_valid_count;
                end
            end else if(MAX_IMAGES>4 && scan_done && !scanning && catalog_lookup_start) begin
                catalog_search_slot<=0;catalog_search_target<=catalog_lookup_index;
                catalog_lookup_busy<=1;catalog_publish<=0;
            end
        end
    end
    fat32_volume_scanner #(.MAX_IMAGES(MAX_IMAGES),.ENABLE_CAPTION(ENABLE_CAPTION)) u_scanner(
        .clk(clk),.rst_n(~modules_rst),.scan_start(scanner_start),.scan_busy(),
        .scan_done(scanner_done),.fs_error(scanner_error),.partition_lba(),
        .sectors_per_cluster(spc),.fat_start_lba(fat_lba),.data_start_lba(data_lba),.max_cluster(max_cluster),
        .resource_valid(resource_valid),.resource0_cluster(cluster0),.resource1_cluster(cluster1),
        .resource2_cluster(cluster2),.resource3_cluster(cluster3),
        .resource0_size(size0),.resource1_size(size1),.resource2_size(size2),.resource3_size(size3),
        .picture_found_valid(picture_found_valid),.picture_found_index(picture_found_index),
        .picture_found_cluster(picture_found_cluster),.picture_found_size(picture_found_size),
        .caption_found_valid(caption_found_valid),.caption_found_name(caption_found_name),
        .caption_found_cluster(caption_found_cluster),.caption_found_size(caption_found_size),
        .audio_found_valid(audio_found_valid),.audio_found_name(audio_found_name),
        .audio_found_cluster(audio_found_cluster),.audio_found_size(audio_found_size),
        .sector_req(scanner_req),.sector_lba(scanner_lba),.sector_busy(busy),
        .sector_valid(sector_valid && scanning),.sector_byte(byte_data),.sector_byte_index(byte_index),
        .sector_done(sector_done && scanning),.sector_error(sector_error)
    );
    fat32_file_streamer u_streamer(
        .clk(clk),.rst_n(~modules_rst),.file_start(stream_start),.data_sector_allow(stream_sector_allow),
        .first_cluster(file_cluster),.file_size(file_size),
        .sectors_per_cluster(spc_q),.fat_start_lba(fat_q),.data_start_lba(data_q),.max_cluster(max_q),
        .file_busy(),.file_done(stream_done),.file_valid(stream_valid),.file_byte(stream_byte),
        .file_byte_offset(stream_offset),.fs_error(stream_error),.sector_req(stream_req),.sector_lba(stream_lba),
        .sector_busy(busy),.sector_valid(sector_valid && !scanning),.sector_byte(byte_data),
        .sector_byte_index(byte_index),.sector_done(sector_done && !scanning),.sector_error(sector_error)
    );
    sd_sector_adapter #(.TIMEOUT_CYCLES(TIMEOUT)) u_adapter(
        .clk(clk),.rst_n(~rst),.abort(load_abort || abort_internal),.sd_init_done(sd_init_done),
        .sector_req(scanning?scanner_req:stream_req),.sector_lba(scanning?scanner_lba:stream_lba),
        .sector_busy(busy),.sector_done(sector_done),.sector_valid(sector_valid),
        .sector_byte(byte_data),.sector_byte_index(byte_index),.sector_error(sector_error),
        .sd_sec_read(sd_sec_read),.sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),.sd_sec_read_end(sd_sec_read_end),
        .sd_sec_read_data(sd_sec_read_data)
    );
    generate if(ENABLE_ADAPTIVE_SCALING!=0) begin : g_scaling
        wire buffered_valid,buffered_ready,buffered_end,buffer_overflow;
        wire [7:0] buffered_byte,buffered_error;
        wire [2:0] scaling_error;
        caption_sector_buffer #(.EXTERNAL_RAM(ENABLE_SHARED_SCALING_RAM)) u_sector_buffer(
            .ram_address(bmp_buffer_address),.ram_write(bmp_buffer_write),
            .ram_write_data(bmp_buffer_write_data),.ram_read_data(bmp_buffer_read_data),
            .clk(clk),.rst(modules_rst),.start(stream_start),
            .file_valid(stream_valid),.file_byte(stream_byte),.file_done(stream_done),.file_error(stream_error),
            .data_sector_allow(stream_sector_allow),.byte_valid(buffered_valid),.byte_data(buffered_byte),
            .byte_ready(buffered_ready),.end_valid(buffered_end),.end_error(buffered_error),.overflow(buffer_overflow));
        bmp_scaling_clock_bridge u_scaler(
            .clk(clk),.rst(modules_rst),.start(stream_start),.file_size(file_size),
            .scale_clk(scale_clk),.scale_rst(scale_rst),
            .byte_valid(buffered_valid),.byte_data(buffered_byte),.byte_ready(buffered_ready),
            .end_valid(buffered_end),.end_error(buffered_error),
            .pixel_valid(pixel_valid),.pixel(bmp_data),.pixel_ready(bmp_pixel_ready && state==LOAD && !load_abort && decoder_error==0),
            .complete(decoder_complete),.error(scaling_error));
        assign decoder_error=buffer_overflow ? 3'd3 : scaling_error;
    end else begin : g_fixed_size
        assign bmp_buffer_address=0;assign bmp_buffer_write=0;assign bmp_buffer_write_data=0;
        assign stream_sector_allow=1'b1;
    fat32_bmp_decoder u_decoder(
        .clk(clk),.rst(modules_rst),.start(stream_start),.file_size(file_size),
        .width_expected(bmp_width),.height_expected(bmp_height),.valid(stream_valid),
        .offset(stream_offset),.data(stream_byte),.done(stream_done),.upstream_error(stream_error),
        .pixel_valid(pixel_valid),.pixel(bmp_data),.complete(decoder_complete),.error(decoder_error)
    );
    end endgenerate
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=IDLE;emit_index<=0;picture_valid<=0;wait_count<=0;file_cluster<=0;file_size<=0;
            scanner_start<=0;stream_start<=0;abort_internal<=0;scan_done<=0;
            scan_found_valid<=0;scan_found_cluster<=0;scan_found_size<=0;scan_found_total<=0;
            bmp_error<=0;load_error<=0;load_done<=0;scan_error<=0;scan_reject<=0;sd_recover<=0;write_req<=0;
            spc_q<=0;fat_q<=0;data_q<=0;max_q<=0;
        end else begin
            scanner_start<=0;stream_start<=0;abort_internal<=0;scan_found_valid<=0;
            if(MAX_IMAGES>4 && state==SCAN && picture_found_valid) picture_valid[picture_found_index]<=1;
            load_error<=0;load_done<=0;scan_error<=0;scan_reject<=0;sd_recover<=0;
            if(load_abort) begin state<=IDLE;write_req<=0;end
            else if(state!=IDLE && !sd_init_done) begin
                bmp_error<=2;sd_recover<=1;abort_internal<=1;write_req<=0;
                if(scanning) begin scan_error<=1;scan_done<=0;end else load_error<=1;
                state<=IDLE;
            end else case(state)
                IDLE: if(scan_start && sd_init_done) begin
                    scan_done<=0;scan_found_total<=0;picture_valid<=0;bmp_error<=0;scanner_start<=1;state<=SCAN;
                end else if(load_start && sd_init_done) begin
                    file_cluster<=load_cluster;file_size<=load_file_size;bmp_error<=0;
                    write_req<=1;wait_count<=0;state<=ACK;
                end
                SCAN: if(scanner_done) begin
                    if(scanner_error!=0 && scanner_error!=8'h22) begin
                        bmp_error<=scanner_error==8'h10 ?(sector_error==3?3:2):scanner_error==8'h23 ? 3 : 1;
                        scan_error<=1;state<=IDLE;
                        if(scanner_error==8'h10) sd_recover<=1;
                    end else begin
                        spc_q<=spc;fat_q<=fat_lba;data_q<=data_lba;max_q<=max_cluster;
                        emit_index<=0;state<=EMIT;
                    end
                end
                EMIT: if(MAX_IMAGES>4) begin
                    // Drain the final serialized write before publishing any record.
                    if(!catalog_write_busy)begin
                        if(emit_index==MAX_IMAGES) begin scan_done<=1;state<=IDLE;end
                        else if(picture_valid[emit_index[IMAGE_BITS-1:0]])state<=READ_ENTRY;
                        else emit_index<=emit_index+1'b1;
                    end
                end else begin
                    if(emit_index==4) begin scan_done<=1;state<=IDLE;end
                    else begin
                        emit_index<=emit_index+1'b1;
                        if(resource_valid[emit_index]) begin
                            scan_found_valid<=1;scan_found_total<=scan_found_total+1'b1;
                            case(emit_index)
                                0:begin scan_found_cluster<=cluster0;scan_found_size<=size0;end
                                1:begin scan_found_cluster<=cluster1;scan_found_size<=size1;end
                                2:begin scan_found_cluster<=cluster2;scan_found_size<=size2;end
                                3:begin scan_found_cluster<=cluster3;scan_found_size<=size3;end
                            endcase
                        end
                    end
                end
                READ_ENTRY: if(catalog_read_valid)state<=EMIT_ENTRY;
                EMIT_ENTRY: begin
                    if(picture_valid[emit_index[IMAGE_BITS-1:0]]) begin
                        scan_found_valid<=1;scan_found_total<=scan_found_total+1'b1;
                        scan_found_cluster<=picture_read[63:32];scan_found_size<=picture_read[31:0];
                    end
                    emit_index<=emit_index+1'b1;state<=EMIT;
                end
                ACK: begin
                    if(write_req_ack) begin write_req<=0;state<=START;end
                    else if(wait_count>=TIMEOUT-1) begin
                        bmp_error<=2;load_error<=1;write_req<=0;state<=IDLE;
                    end else wait_count<=wait_count+1'b1;
                end
                START: begin stream_start<=1;state<=LOAD;end
                LOAD: begin
                    if(sector_done && sector_error!=0) begin
                        bmp_error<=sector_error==3?3:2;load_error<=1;sd_recover<=1;abort_internal<=1;state<=IDLE;
                    end else if(decoder_error!=0 || decoder_complete) begin
                        if(decoder_error!=0) begin
                            bmp_error<=decoder_error;load_error<=1;
                            // Abort the real SD transaction, not just its consumer.
                            sd_recover<=busy;abort_internal<=1;
                        end else load_done<=1;
                        state<=IDLE;
                    end
                end
            endcase
        end
    end
endmodule
