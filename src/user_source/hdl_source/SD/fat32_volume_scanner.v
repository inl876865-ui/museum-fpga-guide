`timescale 1ns/1ps

module fat32_volume_scanner #(parameter integer MAX_IMAGES=4, parameter integer ENABLE_CAPTION=0) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        scan_start,
    output wire        scan_busy,
    output reg         scan_done,
    output reg  [7:0]  fs_error,
    output reg  [31:0] partition_lba,
    output reg  [7:0]  sectors_per_cluster,
    output reg  [31:0] fat_start_lba,
    output reg  [31:0] data_start_lba,
    output reg  [31:0] max_cluster,
    output reg  [3:0]  resource_valid,
    output reg  [31:0] resource0_cluster,
    output reg  [31:0] resource1_cluster,
    output reg  [31:0] resource2_cluster,
    output reg  [31:0] resource3_cluster,
    output reg  [31:0] resource0_size,
    output reg  [31:0] resource1_size,
    output reg  [31:0] resource2_size,
    output reg  [31:0] resource3_size,
    output reg         picture_found_valid,
    output reg [4:0]   picture_found_index,
    output reg [31:0]  picture_found_cluster,picture_found_size,
    output reg caption_found_valid,
    output reg [63:0] caption_found_name,
    output reg [31:0] caption_found_cluster,caption_found_size,
    output reg         audio_found_valid,
    output reg  [87:0] audio_found_name,
    output reg  [31:0] audio_found_cluster,
    output reg  [31:0] audio_found_size,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_busy,
    input  wire        sector_valid,
    input  wire [7:0]  sector_byte,
    input  wire [8:0]  sector_byte_index,
    input  wire        sector_done,
    input  wire [7:0]  sector_error
);

    localparam ERR_NONE            = 8'h00;
    localparam ERR_SECTOR          = 8'h10;
    localparam ERR_BOOT_SIGNATURE  = 8'h20;
    localparam ERR_UNSUPPORTED_BPB = 8'h21;
    localparam ERR_RESOURCE_MISSING= 8'h22;

    localparam ST_IDLE       = 4'd0;
    localparam ST_READ0_REQ  = 4'd1;
    localparam ST_READ0_WAIT = 4'd2;
    localparam ST_BOOT_PARSE = 4'd3;
    localparam ST_BOOT_REQ   = 4'd4;
    localparam ST_BOOT_WAIT  = 4'd5;
    localparam ST_ROOT_REQ   = 4'd6;
    localparam ST_ROOT_WAIT  = 4'd7;
    localparam ST_DIR_SCAN   = 4'd8;
    localparam ST_FINISH     = 4'd9;
    localparam ST_BOOT_LAYOUT= 4'd10;
    localparam ST_BOOT_ROOT  = 4'd11;

    localparam ST_ROOT_COUNT=4'd12, ST_ROOT_CHECK=4'd13, ST_ROOT_ADD=4'd14;
    localparam ST_BOOT_VALIDATE=4'd15;
    reg [31:0] cluster_count,fat_entries_needed,root_offset;
    reg [7:0] root_sector_index;
    reg directory_end;
    reg [4:0] state;
    localparam ST_ROOT_FAT_REQ=5'd16,ST_ROOT_FAT_WAIT=5'd17,ST_ROOT_NEXT=5'd18;
    localparam ST_BOOT_LAYOUT_CHECK=5'd19,ST_BOOT_LAYOUT_COMMIT=5'd20;
    // After layout capture, fat_span holds the low32 sum; its original FAT
    // extent is not consumed again before the next BOOT_PARSE overwrites it.
    // root_lba temporarily holds the pending data base, then ROOT_ADD replaces
    // it with the actual root address before any directory request consumes it.
    localparam ST_ROOT_VALIDATE=5'd21;
    localparam ST_BOOT_SHIFT_COUNT=5'd22,ST_ROOT_SHIFT_OFFSET=5'd23;
    reg [2:0] shift_remaining;
    reg boot_root_reject;
    reg boot_layout_span_carry;
    reg [31:0] boot_layout_total;
    reg boot_layout_end_overflow,boot_layout_extra_reject,boot_layout_reject;
    reg [27:0] root_next_cluster;
    reg [7:0] root_chain_steps;
    reg picture_any;
    reg [5:0] picture_number;
    // Capture only the required boot/MBR fields; parsed fields below are
    // filled directly, without an intermediate sector copy.
    reg [15:0] boot_signature,bpb_sector_bytes,bpb_root_entries;
    reg [15:0] bpb_fat16_size,bpb_ext_flags,bpb_fs_version;
    reg [7:0] boot_jump,bpb_spc,partition_type;
    reg [31:0] partition_offset;
    reg [4:0] directory_entry_index;
    reg [31:0] root_cluster;
    reg boot_fields_valid;
    reg [31:0] total_sectors;
    reg [31:0] fat_sectors;
    reg [7:0] fat_count;
    reg [15:0] reserved_sectors;
    reg [31:0] root_lba;
    // BOOT_LAYOUT stores the raw sector count here; BOOT_ROOT replaces it
    // with the cluster count. No later phase reads the raw sector count.
    wire [31:0] data_sector_count=cluster_count;
    reg [31:0] fat_span;
    reg [2:0] sectors_per_cluster_shift;
    reg [7:0] dir_name0;
    reg [7:0] dir_name1;
    reg [7:0] dir_name2;
    reg [7:0] dir_name3;
    reg [7:0] dir_name4;
    reg [7:0] dir_name5;
    reg [7:0] dir_name6;
    reg [7:0] dir_name7;
    reg [7:0] dir_name8;
    reg [7:0] dir_name9;
    reg [7:0] dir_name10;
    reg       dir_entry_match;
    reg       dir_audio_match;
    reg       dir_caption_match;
    reg [4:0] dir_resource_index;
    reg [15:0] dir_cluster_high;
    reg [15:0] dir_cluster_low;
    reg [31:0] dir_file_size;
    wire dir_cluster_valid;
    reg dir_pcm_lower_nonzero;

    // Byte28 snapshots the already captured cluster, without forwarding a
    // new byte through the comparator. The combined flags retain the original
    // byte28 validity sample even when later fields are edited out of order.
    reg dir_high_less,dir_high_equal,dir_low_le,dir_range_known,dir_at_least_two;
    assign dir_cluster_valid=dir_at_least_two &&
        (dir_range_known ? (dir_high_less || (dir_high_equal && dir_low_le)) : 1'bx);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            dir_high_less<=0;dir_high_equal<=0;dir_low_le<=0;
            dir_range_known<=1;dir_at_least_two<=0;
        end else if(sector_valid && state==ST_ROOT_WAIT && sector_byte_index[4:0]==28) begin
            dir_high_less<=dir_cluster_high<max_cluster[31:16];
            dir_high_equal<=dir_cluster_high==max_cluster[31:16];
            dir_low_le<=dir_cluster_low<=max_cluster[15:0];
            dir_range_known<=(^{dir_cluster_high,dir_cluster_low} !== 1'bx) && (^max_cluster !== 1'bx);
            dir_at_least_two<={dir_cluster_high,dir_cluster_low}>=32'd2;
        end
    end

    // Directory byte31 snapshots are compared, qualified and published in
    // separate clocks. Two payload stages also accept consecutive byte31
    // events, so subsequent bytes cannot overwrite a pending result.
    reg dir_pending0,dir_pending1;
    reg [87:0] dir_publish_name0,dir_publish_name1;
    reg [31:0] dir_publish_cluster0,dir_publish_cluster1;
    reg [31:0] dir_publish_size0,dir_publish_size1;
    reg [4:0] dir_publish_index0,dir_publish_index1;
    reg dir_audio_eligible0,dir_picture_eligible0,dir_caption_eligible0,dir_legacy_eligible0;
    reg dir_picture_size0,dir_caption_size0;
    reg dir_legacy_high_less0,dir_legacy_high_equal0,dir_legacy_low_le0;
    reg dir_legacy_range_known0,dir_legacy_at_least_two0;
    wire dir_legacy_range0=dir_legacy_at_least_two0 &&
        (dir_legacy_range_known0 ? (dir_legacy_high_less0 || (dir_legacy_high_equal0 && dir_legacy_low_le0)) : 1'bx);
    reg dir_audio_eligible1,dir_picture_eligible1,dir_caption_eligible1,dir_legacy_eligible1;

    // A 32-bit shift by seven discards the upper seven FAT-size bits and
    // appends seven zeros. Compare its exact 25-bit quotient, then the
    // required-entry remainder; no new state or validation delay is added.
    wire fat_capacity_known=(^fat_sectors[24:0] !== 1'bx) && (^fat_entries_needed !== 1'bx);
    wire fat_capacity_less=fat_capacity_known ?
        (fat_sectors[24:0]<fat_entries_needed[31:7] ||
         (fat_sectors[24:0]==fat_entries_needed[31:7] && (|fat_entries_needed[6:0]))) : 1'bx;

    // Private directory payloads are consumed only after both valid stages.
    // Keep pending/qualification and all public outputs asynchronously reset;
    // every payload is captured before publication, so no reset mux is needed.
    always @(posedge clk) begin
        if(!rst_n) begin end
        else begin
            if(sector_valid && state==ST_ROOT_WAIT && sector_byte_index[4:0]==31) begin
                dir_publish_name0<={dir_name0,dir_name1,dir_name2,dir_name3,dir_name4,dir_name5,dir_name6,dir_name7,dir_name8,dir_name9,dir_name10};
                dir_publish_cluster0<={dir_cluster_high,dir_cluster_low};
                dir_publish_size0<={sector_byte,dir_file_size[23:0]};
                dir_publish_index0<=dir_resource_index;
            end
            if(dir_pending0) begin
                dir_publish_name1<=dir_publish_name0;
                dir_publish_cluster1<=dir_publish_cluster0;
                dir_publish_size1<=dir_publish_size0;
                dir_publish_index1<=dir_publish_index0;
            end
        end
    end

    assign scan_busy = (state != ST_IDLE);

    function valid_spc;
        input [7:0] value;
        begin
            valid_spc = value != 0 && ((value & (value - 1'b1)) == 0);
        end
    endfunction

    function [2:0] spc_shift;
        input [7:0] value;
        begin
            case (value)
                8'd2:   spc_shift = 3'd1;
                8'd4:   spc_shift = 3'd2;
                8'd8:   spc_shift = 3'd3;
                8'd16:  spc_shift = 3'd4;
                8'd32:  spc_shift = 3'd5;
                8'd64:  spc_shift = 3'd6;
                8'd128: spc_shift = 3'd7;
                default: spc_shift = 3'd0;
            endcase
        end
    endfunction

    // Mutually exclusive scanner phases use the same address adder.
    wire addr_boot = state == ST_BOOT_PARSE;
    wire addr_layout = state == ST_BOOT_LAYOUT;
    wire addr_root = state == ST_ROOT_ADD;
    wire addr_next = state == ST_DIR_SCAN;
    wire addr_fat = state == ST_ROOT_FAT_REQ;
    wire addr_count = state == ST_ROOT_COUNT;
    wire [32:0] boot_span_sum = {17'd0,reserved_sectors} + {1'b0,fat_span};
    wire [31:0] address_a =
        ({32{addr_boot || addr_layout}} & partition_lba) |
        ({32{addr_root}} & data_start_lba) |
        ({32{addr_next}} & sector_lba) |
        ({32{addr_fat}} & fat_start_lba) |
        ({32{addr_count}} & cluster_count);
    wire [31:0] address_b =
        ({32{addr_boot}} & {16'd0,reserved_sectors}) |
        ({32{addr_layout}} & boot_span_sum[31:0]) |
        ({32{addr_root}} & root_offset) |
        ({32{addr_next || addr_count}} & 32'd1) |
        ({32{addr_fat}} & (root_cluster >> 7));
    wire [31:0] address_sum = address_a + address_b;

    task finish_with_error;
        input [7:0] code;
        begin
            fs_error <= code;
            state <= ST_FINISH;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            boot_signature<=0;bpb_sector_bytes<=0;bpb_root_entries<=0;
            bpb_fat16_size<=0;bpb_ext_flags<=0;bpb_fs_version<=0;
            boot_jump<=0;bpb_spc<=0;partition_type<=0;partition_offset<=0;
            root_sector_index<=0;directory_end<=0;cluster_count<=0;fat_entries_needed<=0;root_offset<=0;
            state <= ST_IDLE;
            scan_done <= 1'b0;
            fs_error <= ERR_NONE;
            partition_lba <= 32'd0;
            sectors_per_cluster <= 8'd0;
            fat_start_lba <= 32'd0;
            data_start_lba <= 32'd0;
            max_cluster <= 32'd0;
            resource_valid <= 4'd0;
            picture_found_valid<=0;picture_found_index<=0;picture_found_cluster<=0;picture_found_size<=0;
            picture_any<=0;picture_number<=0;root_next_cluster<=0;root_chain_steps<=0;
            resource0_cluster <= 32'd0;
            resource1_cluster <= 32'd0;
            resource2_cluster <= 32'd0;
            resource3_cluster <= 32'd0;
            resource0_size <= 32'd0;
            resource1_size <= 32'd0;
            resource2_size <= 32'd0;
            resource3_size <= 32'd0;
            audio_found_valid <= 1'b0;
            caption_found_valid<=0;caption_found_name<=0;caption_found_cluster<=0;caption_found_size<=0;
            audio_found_name <= 88'd0;
            audio_found_cluster <= 32'd0;
            audio_found_size <= 32'd0;
            sector_req <= 1'b0;
            sector_lba <= 32'd0;
            directory_entry_index <= 5'd0;
            root_cluster <= 32'd0;
            boot_fields_valid <= 1'b0;
            boot_root_reject<=0;shift_remaining<=0;
            boot_layout_end_overflow<=0;boot_layout_extra_reject<=0;boot_layout_reject<=0;
            total_sectors <= 32'd0;
            fat_sectors <= 32'd0;
            fat_count <= 8'd0;
            reserved_sectors <= 16'd0;
            root_lba <= 32'd0;
            fat_span <= 32'd0;
            sectors_per_cluster_shift <= 3'd0;
            dir_name0 <= 8'd0;
            dir_name1 <= 8'd0;
            dir_name2 <= 8'd0;
            dir_name3 <= 8'd0;
            dir_name4 <= 8'd0;
            dir_name5 <= 8'd0;
            dir_name6 <= 8'd0;
            dir_name7 <= 8'd0;
            dir_name8 <= 8'd0;
            dir_name9 <= 8'd0;
            dir_name10 <= 8'd0;
            dir_entry_match <= 1'b0;
            dir_audio_match <= 1'b0;dir_caption_match<=0;
            dir_resource_index <= 2'd3;
            dir_cluster_high <= 16'd0;
            dir_cluster_low <= 16'd0;
            dir_file_size <= 32'd0;

            dir_pcm_lower_nonzero <= 1'b0;
            dir_pending0<=0;dir_pending1<=0;
            
            
            
            
            dir_audio_eligible0<=0;dir_picture_eligible0<=0;dir_caption_eligible0<=0;dir_legacy_eligible0<=0;
            dir_picture_size0<=0;dir_caption_size0<=0;
            dir_legacy_high_less0<=0;dir_legacy_high_equal0<=0;dir_legacy_low_le0<=0;
            dir_legacy_range_known0<=1;dir_legacy_at_least_two0<=0;
            dir_audio_eligible1<=0;dir_picture_eligible1<=0;dir_caption_eligible1<=0;dir_legacy_eligible1<=0;
        end else begin
            scan_done <= 1'b0;
            sector_req <= 1'b0;
            audio_found_valid <= 1'b0;picture_found_valid<=0;caption_found_valid<=0;
            dir_pending0<=0;dir_pending1<=dir_pending0;
            if(dir_pending0) begin
                
                
                
                
                dir_audio_eligible1<=dir_audio_eligible0;
                dir_picture_eligible1<=dir_picture_eligible0 && dir_picture_size0;
                dir_caption_eligible1<=dir_caption_eligible0 && dir_caption_size0;
                dir_legacy_eligible1<=dir_legacy_eligible0 && dir_legacy_range0 && dir_picture_size0;
            end
            if(dir_pending1) begin
                if(dir_audio_eligible1) begin
                    audio_found_valid<=1;audio_found_name<=dir_publish_name1;
                    audio_found_cluster<=dir_publish_cluster1;audio_found_size<=dir_publish_size1;
                end
                if(dir_caption_eligible1) begin
                    caption_found_valid<=1;caption_found_name<=dir_publish_name1[87:24];
                    caption_found_cluster<=dir_publish_cluster1;caption_found_size<=dir_publish_size1;
                end
                if(dir_picture_eligible1) begin
                    picture_found_valid<=1;picture_any<=1;picture_found_index<=dir_publish_index1;
                    picture_found_cluster<=dir_publish_cluster1;picture_found_size<=dir_publish_size1;
                end
                // Check the committed mask here, so the first duplicate wins
                // even when two qualifying snapshots enter on consecutive clocks.
                if(dir_legacy_eligible1 && !resource_valid[dir_publish_index1]) begin
                    case(dir_publish_index1)
                        0:begin resource0_cluster<=dir_publish_cluster1;resource0_size<=dir_publish_size1;resource_valid[0]<=1;end
                        1:begin resource1_cluster<=dir_publish_cluster1;resource1_size<=dir_publish_size1;resource_valid[1]<=1;end
                        2:begin resource2_cluster<=dir_publish_cluster1;resource2_size<=dir_publish_size1;resource_valid[2]<=1;end
                        3:begin resource3_cluster<=dir_publish_cluster1;resource3_size<=dir_publish_size1;resource_valid[3]<=1;end
                        default:begin end
                    endcase
                end
            end
            if(sector_valid && state==ST_ROOT_FAT_WAIT) begin
                if(sector_byte_index=={root_cluster[6:0],2'b00}) root_next_cluster[7:0]<=sector_byte;
                if(sector_byte_index=={root_cluster[6:0],2'b00}+9'd1) root_next_cluster[15:8]<=sector_byte;
                if(sector_byte_index=={root_cluster[6:0],2'b00}+9'd2) root_next_cluster[23:16]<=sector_byte;
                if(sector_byte_index=={root_cluster[6:0],2'b00}+9'd3) root_next_cluster[27:24]<=sector_byte[3:0];
            end
    // These boot fields are only tested against zero or a fixed value.
    // Keep the field names and encode just those exact comparison classes.
            if (sector_valid && state != ST_ROOT_WAIT && state != ST_ROOT_FAT_WAIT) begin
                case(sector_byte_index)
                    0:boot_jump<=(sector_byte==8'heb || sector_byte==8'he9) ? 8'heb : 8'd0;
                    11:bpb_sector_bytes[7:0]<={7'd0,|sector_byte};
                    12:bpb_sector_bytes[15:8]<=sector_byte==8'd2 ? 8'd2 : 8'd1;
                    13:bpb_spc<=sector_byte;
                    14:reserved_sectors[7:0]<=sector_byte;
                    15:reserved_sectors[15:8]<=sector_byte;
                    16:fat_count<=sector_byte;
                    17:bpb_root_entries[7:0]<={7'd0,|sector_byte};
                    18:bpb_root_entries[15:8]<={7'd0,|sector_byte};
                    22:bpb_fat16_size[7:0]<={7'd0,|sector_byte};
                    23:bpb_fat16_size[15:8]<={7'd0,|sector_byte};
                    32:total_sectors[7:0]<=sector_byte;
                    33:total_sectors[15:8]<=sector_byte;
                    34:total_sectors[23:16]<=sector_byte;
                    35:total_sectors[31:24]<=sector_byte;
                    36:fat_sectors[7:0]<=sector_byte;
                    37:fat_sectors[15:8]<=sector_byte;
                    38:fat_sectors[23:16]<=sector_byte;
                    39:fat_sectors[31:24]<=sector_byte;
                    40:bpb_ext_flags[7:0]<=sector_byte;
                    41:bpb_ext_flags[15:8]<=sector_byte;
                    42:bpb_fs_version[7:0]<={7'd0,|sector_byte};
                    43:bpb_fs_version[15:8]<={7'd0,|sector_byte};
                    44:root_cluster[7:0]<=sector_byte;
                    45:root_cluster[15:8]<=sector_byte;
                    46:root_cluster[23:16]<=sector_byte;
                    47:root_cluster[31:24]<=sector_byte;
                    450:partition_type<=(sector_byte==8'h0b || sector_byte==8'h0c) ? 8'h0b : 8'd0;
                    454:partition_offset[7:0]<=sector_byte;
                    455:partition_offset[15:8]<=sector_byte;
                    456:partition_offset[23:16]<=sector_byte;
                    457:partition_offset[31:24]<=sector_byte;
                    510:boot_signature[7:0]<=sector_byte==8'h55 ? 8'h55 : 8'd0;
                    511:boot_signature[15:8]<=sector_byte==8'haa ? 8'haa : 8'd0;
                    default:begin end
                endcase
            end

            if (sector_valid && state == ST_ROOT_WAIT) begin
                case (sector_byte_index[4:0])
                    5'd0: begin
                        dir_name0 <= sector_byte;
                        if(sector_byte==0) directory_end<=1;
                        dir_entry_match <= 1'b0;
                        dir_audio_match <= 1'b0;dir_caption_match<=0;
                    end
                    5'd1:  dir_name1 <= sector_byte;
                    5'd2:  dir_name2 <= sector_byte;
                    5'd3:  dir_name3 <= sector_byte;
                    5'd4:  dir_name4 <= sector_byte;
                    5'd5: begin
                        dir_name5<=sector_byte;
                        if(dir_name4==" ") picture_number<={2'b00,dir_name3[3:0]};
                        else case(dir_name3[3:0])
                            0:picture_number<={2'b00,dir_name4[3:0]};
                            1:picture_number<=6'd10+dir_name4[3:0];
                            2:picture_number<=6'd20+dir_name4[3:0];
                            3:picture_number<=6'd30+dir_name4[3:0];
                            default:picture_number<=0;
                        endcase
                    end
                    5'd6:  dir_name6 <= sector_byte;
                    5'd7:  dir_name7 <= sector_byte;
                    5'd8:  dir_name8 <= sector_byte;
                    5'd9:  dir_name9 <= sector_byte;
                    5'd10: dir_name10 <= sector_byte;
                    5'd11: begin
                        dir_caption_match<=ENABLE_CAPTION!=0 && !directory_end && dir_name0!=8'he5 &&
                            (sector_byte & 8'hd8)==0 && dir_name8=="C" && dir_name9=="A" && dir_name10=="P";
                        if (!directory_end && dir_name0 != 8'he5 &&
                            (sector_byte & 8'hd8)==0 &&
                            dir_name8 == "P" && dir_name9 == "C" &&
                            dir_name10 == "M")
                            dir_audio_match <= 1'b1;
                        if (!directory_end && (sector_byte & 8'hd8)==0 &&
                            dir_name0 == "P" && dir_name1 == "I" &&
                            dir_name2 == "C" && dir_name3 >= "0" && dir_name3 <= "9" &&
                            (dir_name4==" " || (dir_name4>="0" && dir_name4<="9")) &&
                            (MAX_IMAGES>4 || dir_name4==" ") &&
                            picture_number>=1 && picture_number<=MAX_IMAGES &&
                            dir_name5 == " " && dir_name6 == " " &&
                            dir_name7 == " " && dir_name8 == "B" &&
                            dir_name9 == "M" && dir_name10 == "P") begin
                            dir_entry_match <= 1'b1;
                            dir_resource_index <= picture_number - 1'b1;
                        end
                    end
                    5'd20: dir_cluster_high[7:0] <= sector_byte;
                    5'd21: dir_cluster_high[15:8] <= sector_byte;
                    5'd26: dir_cluster_low[7:0] <= sector_byte;
                    5'd27: dir_cluster_low[15:8] <= sector_byte;
                    5'd28: begin
                        dir_file_size[7:0] <= sector_byte;

                    end
                    5'd29: dir_file_size[15:8] <= sector_byte;
                    5'd30: begin
                        dir_file_size[23:16] <= sector_byte;
                        dir_pcm_lower_nonzero <= (|{sector_byte,dir_file_size[15:1]});
                    end
                    5'd31: begin
                        dir_file_size[31:24] <= sector_byte;
                        dir_pending0<=1;
                        
                        
                        
                        
                        dir_audio_eligible0<=dir_audio_match && dir_cluster_valid &&
                            ((|sector_byte) || dir_pcm_lower_nonzero) && !dir_file_size[0];
                        dir_picture_eligible0<=dir_entry_match && dir_cluster_valid;
                        dir_caption_eligible0<=ENABLE_CAPTION!=0 && dir_caption_match && dir_cluster_valid;
                        // Legacy resource slots deliberately use the live cluster;
                        // PIC/PCM/CAP retain the original byte28 validity sample.
                        dir_legacy_eligible0<=dir_entry_match && dir_resource_index<4;
                        dir_legacy_high_less0<=dir_cluster_high<max_cluster[31:16];
                        dir_legacy_high_equal0<=dir_cluster_high==max_cluster[31:16];
                        dir_legacy_low_le0<=dir_cluster_low<=max_cluster[15:0];
                        dir_legacy_range_known0<=(^{dir_cluster_high,dir_cluster_low} !== 1'bx) && (^max_cluster !== 1'bx);
                        dir_legacy_at_least_two0<={dir_cluster_high,dir_cluster_low}>=32'd2;
                        dir_picture_size0<={sector_byte,dir_file_size[23:0]}>=54 &&
                            {sector_byte,dir_file_size[23:0]}<=16777216;
                        dir_caption_size0<={sector_byte,dir_file_size[23:0]}>=152 &&
                            {sector_byte,dir_file_size[23:0]}<=149552;
                    end
                    default: begin end
                endcase
            end

            case (state)
                ST_IDLE: if (scan_start) begin
                    picture_any<=0;root_chain_steps<=0;
                    fs_error <= ERR_NONE;
                    partition_lba <= 32'd0;
                    resource_valid <= 4'd0;
                    root_sector_index<=0;directory_end<=0;
                    state <= ST_READ0_REQ;
                end
                ST_READ0_REQ: if (!sector_busy) begin
                    sector_lba <= 32'd0;
                    sector_req <= 1'b1;
                    state <= ST_READ0_WAIT;
                end
                ST_READ0_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else if (boot_signature != 16'haa55)
                        finish_with_error(ERR_BOOT_SIGNATURE);
                    else if ((boot_jump == 8'heb || boot_jump == 8'he9) && bpb_sector_bytes==512) begin
                        partition_lba <= 32'd0;
                        state <= ST_BOOT_PARSE;
                    end else if (partition_type == 8'h0b || partition_type == 8'h0c) begin
                        partition_lba <= partition_offset;
                        sector_lba <= partition_offset;
                        state <= ST_BOOT_REQ;
                    end else begin
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    end
                end
                ST_BOOT_REQ: if (!sector_busy) begin
                    sector_req <= 1'b1;
                    state <= ST_BOOT_WAIT;
                end
                ST_BOOT_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else if (boot_signature != 16'haa55)
                        finish_with_error(ERR_BOOT_SIGNATURE);
                    else
                        state <= ST_BOOT_PARSE;
                end
                ST_BOOT_PARSE: begin
                    boot_fields_valid <= bpb_sector_bytes == 16'd512 && valid_spc(bpb_spc) &&
                        reserved_sectors != 0 && (fat_count == 1 || fat_count == 2) &&
                        bpb_root_entries == 0 && bpb_fat16_size == 0 && bpb_fs_version == 0 &&
                        (bpb_ext_flags&16'h0080) == 0;
                    sectors_per_cluster <= bpb_spc;
                    sectors_per_cluster_shift <= spc_shift(bpb_spc);
                    fat_span <= fat_count == 2 ? (fat_sectors << 1) : fat_sectors;
                    fat_start_lba <= address_sum;
                    state <= ST_BOOT_VALIDATE;
                end
                ST_BOOT_VALIDATE: begin
                    if (!boot_fields_valid || total_sectors == 0 || fat_sectors == 0 || root_cluster < 2)
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    else
                        state <= ST_BOOT_LAYOUT;
                end
                ST_BOOT_LAYOUT: begin
                    // Freeze the same operands at the old layout-consumption
                    // edge; later bytes cannot mix different boot snapshots.
                    fat_span<=boot_span_sum[31:0];boot_layout_span_carry<=boot_span_sum[32];
                    boot_layout_total<=total_sectors;
                    root_lba<=address_sum;
                    boot_layout_end_overflow<=({1'b0,partition_lba}+{1'b0,total_sectors})>33'h0ffffffff;
                    boot_layout_extra_reject<=(fat_count==2 && fat_sectors[31]) || fat_sectors>32'h01ffffff;
                    state<=ST_BOOT_LAYOUT_CHECK;
                end
                ST_BOOT_LAYOUT_CHECK: begin
                    boot_layout_reject<={boot_layout_span_carry,fat_span}>={1'b0,boot_layout_total} ||
                        boot_layout_end_overflow || boot_layout_extra_reject;
                    state<=ST_BOOT_LAYOUT_COMMIT;
                end
                ST_BOOT_LAYOUT_COMMIT: begin
                    // Exactly the same value/error, published two clocks later.
                    cluster_count<=boot_layout_total-fat_span;
                    if(boot_layout_reject) finish_with_error(ERR_UNSUPPORTED_BPB);
                    else begin data_start_lba<=root_lba;state<=ST_BOOT_ROOT;end
                end
                ST_BOOT_ROOT: begin
                    root_offset<=root_cluster-2;
                    shift_remaining<=sectors_per_cluster_shift;state<=ST_BOOT_SHIFT_COUNT;
                end
                ST_BOOT_SHIFT_COUNT: begin
                    if(shift_remaining==0)state<=ST_ROOT_COUNT;
                    else begin cluster_count<={1'b0,cluster_count[31:1]};shift_remaining<=shift_remaining-1'b1;end
                end
                ST_ROOT_COUNT: begin
                    max_cluster<=address_sum;
                    fat_entries_needed<=cluster_count+2;
                    shift_remaining<=sectors_per_cluster_shift;state<=ST_ROOT_SHIFT_OFFSET;
                end
                ST_ROOT_SHIFT_OFFSET: begin
                    if(shift_remaining==0)state<=ST_ROOT_CHECK;
                    else begin root_offset<={root_offset[30:0],1'b0};shift_remaining<=shift_remaining-1'b1;end
                end
                ST_ROOT_CHECK: begin
                    boot_root_reject<=cluster_count<65525 || cluster_count>32'h0fffffee ||
                        root_cluster>max_cluster || fat_capacity_less;
                    state<=ST_ROOT_VALIDATE;
                end
                ST_ROOT_VALIDATE: begin
                    if(boot_root_reject)finish_with_error(ERR_UNSUPPORTED_BPB);
                    else state<=ST_ROOT_ADD;
                end
                ST_ROOT_ADD: begin
                    root_lba<=address_sum;
                    sector_lba<=address_sum;
                    state<=ST_ROOT_REQ;
                end
                ST_ROOT_REQ: if (!sector_busy) begin
                    dir_entry_match <= 1'b0;
                    sector_req <= 1'b1;
                    state <= ST_ROOT_WAIT;
                end
                ST_ROOT_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else begin
                        directory_entry_index <= 5'd0;
                        state <= ST_DIR_SCAN;
                    end
                end
                ST_DIR_SCAN: if(!dir_pending0 && !dir_pending1) begin
                    if(directory_end) begin
                        if(resource_valid!=0 || picture_any) state<=ST_FINISH;
                        else finish_with_error(ERR_RESOURCE_MISSING);
                    end else if(root_sector_index+1>=sectors_per_cluster) begin
                        if(MAX_IMAGES>4) state<=ST_ROOT_FAT_REQ;
                        else if(resource_valid!=0) state<=ST_FINISH;
                        else finish_with_error(ERR_RESOURCE_MISSING);
                    end else begin
                        root_sector_index<=root_sector_index+1'b1;
                        sector_lba<=address_sum;
                        state<=ST_ROOT_REQ;
                    end
                end
                ST_ROOT_FAT_REQ: if(!sector_busy) begin
                    sector_lba<=address_sum;
                    sector_req<=1;root_next_cluster<=0;state<=ST_ROOT_FAT_WAIT;
                end
                ST_ROOT_FAT_WAIT: if(sector_done) begin
                    if(sector_error!=0) finish_with_error(ERR_SECTOR);
                    else state<=ST_ROOT_NEXT;
                end
                ST_ROOT_NEXT: begin
                    if(root_next_cluster>=28'hffffff8) begin
                        if(picture_any) state<=ST_FINISH;
                        else finish_with_error(ERR_RESOURCE_MISSING);
                    end else if(root_next_cluster<2 || root_next_cluster>max_cluster ||
                                root_next_cluster==root_cluster || root_chain_steps==127)
                        finish_with_error(8'h23);
                    else begin
                        root_cluster<={4'd0,root_next_cluster};root_offset<=root_next_cluster-2;root_sector_index<=0;
                        root_chain_steps<=root_chain_steps+1'b1;state<=ST_ROOT_COUNT;
                    end
                end
                ST_FINISH: if(!dir_pending0 && !dir_pending1) begin
                    scan_done <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
