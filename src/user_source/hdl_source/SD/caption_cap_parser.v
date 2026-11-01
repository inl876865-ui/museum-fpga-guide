`timescale 1ns/1ps
// Streaming CAP v1 validator. Only a validated index and CRC-complete bitmap publish.
module caption_cap_parser #(parameter integer ENABLE_CACHE_FEEDBACK=0, parameter integer BAD_CUES_RAM=0) (
    input wire clk,rst,start,reuse_index,
    input wire pixel_clk,
    input wire [17:0] expected_file_size,
    input wire [63:0] expected_name,
    input wire [31:0] expected_pcm_bytes,request_session,
    input wire byte_valid,
    input wire [7:0] byte_data,
    output wire byte_ready,
    input wire end_valid,
    input wire [7:0] end_error,
    input wire wanted_valid,
    input wire [6:0] wanted_cue,
    input wire bank0_free,bank1_free,
    input wire cached0,cached1,
    input wire [5:0] cached_cue0,cached_cue1,
    output wire [5:0] stream_cue,
    output wire waiting_for_demand,
    output wire wanted_bad,next_bad,bad_queries_ready,
    output reg bank_reserve,bank_write,bank_publish,bank_discard,
    output reg bank_select,
    output reg [11:0] bank_address,
    output reg [7:0] bank_data,
    output reg [5:0] publish_cue,
    output reg header_valid,header_timed,file_complete,failed,
    output reg [3:0] error_code,
    output reg [6:0] cue_count,
    output reg [31:0] cycle_samples,header_session,
    output reg [63:0] bad_cues,
    input wire [8:0] pixel_index_address,
    output reg [31:0] pixel_index_data
);
    // The pixel port retains the CAP index verbatim. Validation uses a small
    // byte-wide work RAM, so the same 8-bit ALU checks every 32-bit field.
    (* ram_style="bram" *) reg [31:0] index_words[0:511];
    (* ram_style="bram" *) reg [7:0] check_bytes[0:127];
    localparam HEADER=0,INIT_CHECK=1,INDEX=2,WIDTH_READ=3,WIDTH_TEST=4,
               SHAPE_READ=5,SHAPE_TEST=6,WIDTH_COUNT=7,CHECK_READ=8,CHECK_EXEC=9,
               LOAD_ADDRESS=10,LOAD_WAIT=11,LOAD_LATCH=12,WAIT_DEMAND=13,
               WAIT_BANK=14,POINTS=15,FINISH=16,ERROR=17,CLEAR_BAD=18;
    reg [4:0] state;
    reg [17:0] position;
    reg [23:0] word_shift;
    reg [31:0] loader_word;
    reg [7:0] pending_byte;
    reg waiting_crc,commit_byte;
    reg [2:0] crc_count;
    reg [31:0] crc_value,cached_index_crc;
    wire [31:0] next_crc=crc_value[0] ? (crc_value>>1)^32'hedb88320 : crc_value>>1;
    wire [31:0] assembled_word={pending_byte,word_shift};
    wire do_crc=state==INDEX || state==POINTS || state==HEADER && position<44;
    reg header_shape_ok,reusing,file_color_v2;
    reg [6:0] table_entry;
    reg [2:0] table_word,load_word;
    reg [5:0] point_cue;
    reg [17:0] entry_offset;
    reg [11:0] point_length,point_position;
    reg retaining;
    reg [5:0] clear_bad_address;
    reg [6:0] init_address;
    reg [7:0] init_data;
    reg [7:0] work_a,work_b;
    reg [6:0] a_base,b_base,d_base;
    reg [3:0] check_op;
    reg [1:0] check_byte;
    reg [6:0] width_value;
    reg [5:0] width_count;
    reg carry,word_zero;
    reg subtract,copy_a,write_result;
    reg [6:0] work_read_a,work_read_b;
    wire [8:0] arithmetic={1'b0,work_a}+{1'b0,(work_b^{8{subtract}})}+carry;
    wire [7:0] result_byte=copy_a ? work_a : arithmetic[7:0];
    // CAPv2 reserves only index word7 bits[2:0] for the palette ID.
    // Mask those bits for the existing zero validator; CAPv1 stays strict.
    wire result_zero=word_zero && (check_op==14 && file_color_v2 && check_byte==0 ?
        result_byte[7:3]==0 : result_byte==0);
    wire [11:0] payload_start=12'd48+{cue_count,5'd0};
    reg [7:0] header_expected;
    reg header_byte_ok;
    wire index_write=commit_byte && state==INDEX && position[1:0]==3 && !reusing && !failed && !start && !(end_valid && end_error!=0);
    wire [8:0] index_write_address={table_entry[5:0],table_word};
    wire [8:0] loader_address={point_cue,load_word};
    always @(posedge clk) begin
        if(index_write) index_words[index_write_address]<=assembled_word;
        else loader_word<=index_words[loader_address];
    end
    always @(posedge pixel_clk) pixel_index_data<=index_words[pixel_index_address];

    // Work bytes: 0..31 current entry, 32 previous end, 36 next bitmap,
    // 40 PCM sample limit, 44 file size, 48 duration, 52 bitmap length,
    // 56 TXT duration. 80..103 are four-byte constants.
    always @* begin
        case(check_op)
            0:begin a_base=4;b_base=0;d_base=48;end
            1:begin a_base=0;b_base=32;d_base=0;end
            2:begin a_base=40;b_base=4;d_base=0;end
            3:begin a_base=48;b_base=84;d_base=0;end
            4:begin a_base=80;b_base=80;d_base=52;end
            5:begin a_base=96;b_base=80;d_base=56;end
            6:begin a_base=52;b_base=88;d_base=52;end
            7:begin a_base=56;b_base=92;d_base=56;end
            8:begin a_base=16;b_base=52;d_base=0;end
            9:begin a_base=12;b_base=36;d_base=0;end
            10:begin a_base=12;b_base=16;d_base=36;end
            11:begin a_base=44;b_base=36;d_base=0;end
            12:begin a_base=48;b_base=56;d_base=0;end
            13:begin a_base=24;b_base=100;d_base=0;end
            14:begin a_base=28;b_base=80;d_base=0;end
            default:begin a_base=4;b_base=80;d_base=32;end
        endcase
        work_read_a={a_base[6:2],check_byte};work_read_b={b_base[6:2],check_byte};
        if(state==WIDTH_READ) begin work_read_a=8;work_read_b=9;end
        if(state==SHAPE_READ) begin work_read_a=10;work_read_b=11;end
        init_data=0;
        case(init_address)
            36:init_data=payload_start[7:0];37:init_data={4'd0,payload_start[11:8]};
            40:init_data=expected_pcm_bytes[8:1];41:init_data=expected_pcm_bytes[16:9];
            42:init_data=expected_pcm_bytes[24:17];43:init_data={1'b0,expected_pcm_bytes[31:25]};
            44:init_data=expected_file_size[7:0];45:init_data=expected_file_size[15:8];46:init_data={6'd0,expected_file_size[17:16]};
            84:init_data=8'hc0;85:init_data=8'h12;
            88:init_data=8'd72;
            93:init_data=8'h96;
            96:init_data=8'h00;97:init_data=8'hc5;98:init_data=8'h0d;
            100:init_data=8'hc3;101:init_data=8'hf5;102:init_data=8'h28;
            default:begin end
        endcase
    end
    // One write/read port and one independent read port infer a small BRAM.
    // Read the write address during a write cycle; this private value is never
    // consumed until WIDTH_READ/SHAPE_READ/CHECK_READ refreshes the operand.
    // Constant read enable avoids the write-priority chain on the BRAM output.
    reg work_write;
    reg [6:0] work_address;
    reg [7:0] work_write_data;
    always @* begin
        work_write=0;work_address=work_read_a;work_write_data=0;
        if(state==INIT_CHECK) begin work_write=1;work_address=init_address;work_write_data=init_data;end
        else if(commit_byte && state==INDEX && !reusing) begin work_write=1;work_address={table_word,position[1:0]};work_write_data=pending_byte;end
        else if(state==CHECK_EXEC && write_result) begin work_write=1;work_address={d_base[6:2],check_byte};work_write_data=result_byte;end
    end
    always @(posedge clk) begin
        if(work_write) check_bytes[work_address]<=work_write_data;
        work_a<=check_bytes[work_address];
        work_b<=check_bytes[work_read_b];
    end

    // Header comparison is byte-wide, including full 64-bit short name and CRC.
    always @* begin
        header_expected=0;header_byte_ok=1;
        case(position[5:0])
            0:header_expected=8'h46;1:header_expected=8'h43;2:header_expected=8'h41;3:header_expected=8'h50;
            4:begin header_expected=reusing ? (file_color_v2 ? 8'd2 : 8'd1) : pending_byte;header_byte_ok=pending_byte==1 || pending_byte==2;end
            6:begin header_expected=reusing ? {7'd0,header_timed} : pending_byte;header_byte_ok=pending_byte<=1;end
            8:header_expected=expected_file_size[7:0];9:header_expected=expected_file_size[15:8];10:header_expected={6'd0,expected_file_size[17:16]};
            12:begin header_expected=reusing ? {1'b0,cue_count} : pending_byte;header_byte_ok=pending_byte>=1 && pending_byte<=64;end
            14:header_expected=24;15:header_expected=1;
            16:header_expected=8'h80;17:header_expected=8'hbb;
            20:header_expected=expected_pcm_bytes[7:0];21:header_expected=expected_pcm_bytes[15:8];
            22:header_expected=expected_pcm_bytes[23:16];23:header_expected=expected_pcm_bytes[31:24];
            24:header_expected=expected_name[63:56];25:header_expected=expected_name[55:48];26:header_expected=expected_name[47:40];27:header_expected=expected_name[39:32];
            28:header_expected=expected_name[31:24];29:header_expected=expected_name[23:16];30:header_expected=expected_name[15:8];31:header_expected=expected_name[7:0];
            32:header_expected=48;
            36:header_expected=payload_start[7:0];37:header_expected={4'd0,payload_start[11:8]};
            40,41,42,43:header_expected=reusing ? cached_index_crc[7:0] : pending_byte;
            44:header_expected=~crc_value[7:0];45:header_expected=~crc_value[15:8];
            46:header_expected=~crc_value[23:16];47:header_expected=~crc_value[31:24];
            default:begin end
        endcase
        header_byte_ok=header_byte_ok && pending_byte==header_expected;
    end
    assign byte_ready=(state==HEADER || state==INDEX || state==POINTS) && !waiting_crc && !commit_byte && !failed;
    wire [6:0] next_wanted=wanted_cue+1'b1<cue_count ? wanted_cue+1'b1 : header_timed ? 7'd64 : 7'd0;
    wire mark_bad_cue=!start && !failed && commit_byte && state==POINTS && point_position+1'b1>=point_length && ~crc_value!=loader_word;
    wire point_bad;
    // The compatibility vector remains complete. Production may leave it
    // unconnected and consume the three coherent, synchronous RAM queries.
    generate if(BAD_CUES_RAM!=0) begin:g_bad_ram
        (* ram_style="bram" *) reg bad_lookup[0:63];
        (* ram_style="bram" *) reg bad_point[0:63];
        reg wanted_q,next_q,point_q,queries_valid;
        reg [5:0] wanted_tag,next_tag;
        always @(posedge clk) begin
            if(state==CLEAR_BAD) begin bad_lookup[clear_bad_address]<=0;bad_point[clear_bad_address]<=0;end
            else if(mark_bad_cue) begin bad_lookup[point_cue]<=1;bad_point[point_cue]<=1;end
            else begin wanted_q<=bad_lookup[wanted_cue[5:0]];point_q<=bad_point[point_cue];end
            next_q<=bad_lookup[next_wanted[5:0]];
            wanted_tag<=wanted_cue[5:0];next_tag<=next_wanted[5:0];
            queries_valid<=state!=CLEAR_BAD && !mark_bad_cue;
        end
        assign wanted_bad=wanted_q;
        assign next_bad=next_q;
        assign point_bad=point_q;
        assign bad_queries_ready=queries_valid && wanted_tag==wanted_cue[5:0] && next_tag==next_wanted[5:0];
    end else begin:g_bad_registers
        assign wanted_bad=bad_cues[wanted_cue[5:0]];
        assign next_bad=bad_cues[next_wanted[5:0]];
        assign point_bad=bad_cues[point_cue];
        assign bad_queries_ready=1'b1;
    end endgenerate
    wire already_cached=ENABLE_CACHE_FEEDBACK!=0 && ((cached0 && cached_cue0==point_cue) || (cached1 && cached_cue1==point_cue));
    wire current_cached=(cached0 && cached_cue0==wanted_cue) || (cached1 && cached_cue1==wanted_cue) || wanted_bad;
    wire next_cached=next_wanted==64 || (cached0 && cached_cue0==next_wanted) || (cached1 && cached_cue1==next_wanted) || next_bad;
    wire pause_fetch=!bad_queries_ready || ENABLE_CACHE_FEEDBACK!=0 && wanted_valid && (wanted_cue==64 || current_cached && next_cached);
    wire [6:0] point_predecessor={1'b0,point_cue}-7'd1;
    wire [6:0] last_cue=cue_count-7'd1;
    wire wanted_is_next=(point_cue!=0 && wanted_cue==point_predecessor && {1'b0,point_cue}<cue_count) ||
        (point_cue==0 && !header_timed && (cue_count==0 || wanted_cue>=last_cue));
    wire eligible=wanted_valid && wanted_cue<64 && !already_cached && !point_bad && (point_cue==wanted_cue || wanted_is_next);
    assign stream_cue=point_cue;
    assign waiting_for_demand=state==WAIT_DEMAND || state==WAIT_BANK;
    reg index_reject;
    always @* begin
        index_reject=0;
        case(state)
            WIDTH_TEST:index_reject=work_a[2:0]!=0 || work_b>3 || {work_b[1:0],work_a[7:3]}==0 || {work_b[1:0],work_a[7:3]}>96;
            SHAPE_TEST:index_reject=work_a!=24 || work_b!=0;
            WIDTH_COUNT:index_reject=width_value!=0 && width_value<3;
            CHECK_EXEC:if(check_byte==3) case(check_op)
                0:index_reject=!arithmetic[8] || result_zero;
                1:index_reject=!arithmetic[8] || !header_timed && !result_zero;
                2,3:index_reject=header_timed && !arithmetic[8];
                8,9,14:index_reject=!result_zero;
                10:index_reject=arithmetic[8];
                11:index_reject=!arithmetic[8] || table_entry+1'b1>=cue_count && !result_zero;
                12,13:index_reject=!header_timed && !result_zero;
                15:index_reject=table_entry+1'b1>=cue_count && ~crc_value!=cached_index_crc;
                default:begin end
            endcase
            INDEX:index_reject=reusing && commit_byte && position[1:0]==3 && table_word==7 && table_entry+1'b1>=cue_count && ~crc_value!=cached_index_crc;
            default:begin end
        endcase
    end
    wire header_reject=commit_byte && state==HEADER && position==47 && (!header_shape_ok || !header_byte_ok);
    wire transport_reject=(end_valid && end_error!=0) ||
        (state==WAIT_DEMAND && wanted_valid && !pause_fetch && position!=entry_offset) ||
        (state==FINISH && end_valid && !waiting_crc && !commit_byte && position!=expected_file_size) ||
        (end_valid && !byte_valid && !waiting_crc && !commit_byte && (state==HEADER || state==INDEX || state==POINTS));
    task begin_check;
        input [3:0] op;
        begin
            check_op<=op;check_byte<=0;
            // Decode once on the same edge as the selected operation.
            subtract<=!(op==4 || op==5 || op==6 || op==7 || op==10 || op==15);
            copy_a<=op==4 || op==5 || op==15;
            write_result<=op==0 || op==4 || op==5 || op==6 || op==7 || op==10 || op==15;
            carry<=!(op==4 || op==5 || op==6 || op==7 || op==10 || op==15);
            word_zero<=1;state<=CHECK_READ;
        end
    endtask
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=BAD_CUES_RAM!=0 ? CLEAR_BAD : HEADER;clear_bad_address<=0;position<=0;word_shift<=0;pending_byte<=0;waiting_crc<=0;commit_byte<=0;crc_count<=0;crc_value<=32'hffffffff;
            cached_index_crc<=0;header_shape_ok<=1;reusing<=0;file_color_v2<=0;table_entry<=0;table_word<=0;load_word<=0;point_cue<=0;
            entry_offset<=0;point_length<=0;point_position<=0;retaining<=0;init_address<=32;
            check_op<=0;check_byte<=0;width_value<=0;width_count<=0;carry<=0;word_zero<=0;subtract<=1;copy_a<=0;write_result<=1;
            bank_reserve<=0;bank_write<=0;bank_publish<=0;bank_discard<=0;bank_select<=0;bank_address<=0;bank_data<=0;publish_cue<=0;
            header_valid<=0;header_timed<=0;cue_count<=0;cycle_samples<=0;header_session<=0;
            file_complete<=0;failed<=0;error_code<=0;bad_cues<=0;
        end else begin
            bank_reserve<=0;bank_write<=0;bank_publish<=0;bank_discard<=0;
            if(start) begin
                state<=BAD_CUES_RAM!=0 && (!reuse_index || !header_valid || header_session!=request_session) ? CLEAR_BAD : HEADER;clear_bad_address<=0;position<=0;waiting_crc<=0;commit_byte<=0;crc_value<=32'hffffffff;
                header_shape_ok<=expected_file_size>=152 && expected_file_size<=149552 && expected_pcm_bytes!=0 && !expected_pcm_bytes[0];
                reusing<=reuse_index && header_valid && header_session==request_session;
                if(!reuse_index || !header_valid || header_session!=request_session) begin header_valid<=0;bad_cues<=0;cycle_samples<=0;file_color_v2<=0;end
                table_entry<=0;table_word<=0;load_word<=0;point_cue<=0;retaining<=0;
                header_session<=request_session;file_complete<=0;failed<=0;error_code<=0;
            end else if(!failed) begin
                if(byte_valid && byte_ready) begin
                    pending_byte<=byte_data;
                    if(do_crc) begin crc_value<=crc_value^{24'd0,byte_data};crc_count<=0;waiting_crc<=1;end
                    else commit_byte<=1;
                end
                if(waiting_crc) begin
                    crc_value<=next_crc;
                    if(crc_count==7) begin waiting_crc<=0;commit_byte<=1;end
                    else crc_count<=crc_count+1'b1;
                end
                if(commit_byte) begin
                    commit_byte<=0;position<=position+1'b1;
                    if(state!=POINTS) word_shift<=assembled_word[31:8];
                    if(state==HEADER) begin
                        header_shape_ok<=header_shape_ok && header_byte_ok;
                        if(position==4) file_color_v2<=pending_byte==2;
                        if(position==6 && !reusing) header_timed<=pending_byte[0];
                        if(position==12 && !reusing) cue_count<=pending_byte[6:0];
                        if(position>=40 && position<44) cached_index_crc<={pending_byte,cached_index_crc[31:8]};
                        if(position==47) begin
                            init_address<=32;state<=INIT_CHECK;crc_value<=32'hffffffff;
                        end
                    end else if(state==INDEX) begin
                        if(position[1:0]==3) begin
                            if(table_word==1 && !reusing) cycle_samples<=assembled_word;
                            if(table_word==7) begin
                                table_word<=0;
                                if(reusing) begin
                                    if(table_entry+1'b1>=cue_count) begin
                                        header_valid<=1;load_word<=3;point_cue<=0;state<=LOAD_ADDRESS;
                                    end else table_entry<=table_entry+1'b1;
                                end else state<=WIDTH_READ;
                            end else table_word<=table_word+1'b1;
                        end
                    end else if(state==POINTS) begin
                        if(retaining) begin bank_write<=1;bank_address<=point_position;bank_data<=pending_byte;end
                        point_position<=point_position+1'b1;
                        if(point_position+1'b1>=point_length) begin
                            if(~crc_value!=loader_word) begin bad_cues[point_cue]<=1;if(retaining) bank_discard<=1;end
                            else if(retaining) begin
                                if(eligible) begin bank_publish<=1;publish_cue<=point_cue;end else bank_discard<=1;
                            end
                            retaining<=0;
                            if({1'b0,point_cue}+1'b1>=cue_count) state<=FINISH;
                            else begin point_cue<=point_cue+1'b1;load_word<=3;state<=LOAD_ADDRESS;end
                        end
                    end
                end
                case(state)
                    CLEAR_BAD:if(clear_bad_address==63) state<=HEADER;else clear_bad_address<=clear_bad_address+1'b1;
                    INIT_CHECK: begin
                        if(init_address==47) init_address<=80;
                        else if(init_address==103) state<=INDEX;
                        else init_address<=init_address+1'b1;
                    end
                    WIDTH_READ:state<=WIDTH_TEST;
                    WIDTH_TEST:begin
                        width_value<={work_b[1:0],work_a[7:3]};width_count<=0;
                        state<=SHAPE_READ;
                    end
                    SHAPE_READ:state<=SHAPE_TEST;
                    SHAPE_TEST:state<=WIDTH_COUNT;
                    WIDTH_COUNT:begin
                        if(width_value==0) begin_check(0);
                        else begin width_value<=width_value-3; width_count<=width_count+1'b1;end
                    end
                    CHECK_READ:state<=CHECK_EXEC;
                    CHECK_EXEC:begin
                        carry<=arithmetic[8];word_zero<=result_zero;
                        if(check_byte!=3) begin check_byte<=check_byte+1'b1;state<=CHECK_READ;end
                        else begin
                            if(check_op==7 && width_count>1) begin
                                width_count<=width_count-1'b1;begin_check(6);
                            end else if(check_op==15) begin
                                if(table_entry+1'b1>=cue_count) begin
                                    header_valid<=1;point_cue<=0;load_word<=3;state<=LOAD_ADDRESS;
                                end else begin table_entry<=table_entry+1'b1;state<=INDEX;end
                            end else begin_check(check_op+1'b1);
                        end
                    end
                    LOAD_ADDRESS:state<=LOAD_WAIT;
                    LOAD_WAIT:state<=LOAD_LATCH;
                    LOAD_LATCH:begin
                        case(load_word)
                            3:entry_offset<=loader_word[17:0];
                            4:point_length<=loader_word[11:0];
                            5:begin end
                            default:begin end
                        endcase
                        if(load_word==5) state<=WAIT_DEMAND;
                        else begin load_word<=load_word+1'b1;state<=LOAD_ADDRESS;end
                    end
                    WAIT_DEMAND:if(wanted_valid && !pause_fetch) begin
                        if(eligible && !bank0_free && !bank1_free) state<=WAIT_BANK;
                        else begin
                            retaining<=eligible;bank_select<=!bank0_free && bank1_free;if(eligible) bank_reserve<=1;
                            point_position<=0;crc_value<=32'hffffffff;state<=POINTS;
                        end
                    end
                    WAIT_BANK:if(!eligible || bank0_free || bank1_free) state<=WAIT_DEMAND;
                    FINISH:if(end_valid && !waiting_crc && !commit_byte) begin
                        file_complete<=1;
                    end
                    default:begin end
                endcase
                if(header_reject || index_reject || transport_reject) begin
                    failed<=1;header_valid<=0;state<=ERROR;retaining<=0;
                    error_code<=transport_reject ? 4'd3 : header_reject ? 4'd1 : 4'd2;
                    bank_write<=0;bank_publish<=0;bank_reserve<=0;if(retaining) bank_discard<=1;
                end
            end
        end
    end
endmodule
