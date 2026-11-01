`timescale 1ns/1ps
// Bitmap bytes cross through dual-port RAM; only coherent ownership crosses CDC.
module caption_buffers (
    input wire write_clk,write_rst,pixel_clk,pixel_rst,
    input wire [31:0] publish_session,
    input wire reserve,write,publish,discard,abort_write,write_bank,
    input wire [11:0] write_address,
    input wire [7:0] write_data,
    input wire [5:0] publish_cue,
    input wire release0,release1,
    input wire [31:0] release_session0,release_session1,
    output wire free0,free1,
    output wire valid0,valid1,
    output wire [31:0] session0,session1,
    output wire [5:0] cue0,cue1,
    input wire [11:0] pixel_address,
    input wire pixel_bank,
    output wire [7:0] pixel_byte,
    output reg ownership_error,
    output wire any_reserved,
    output wire source_cached0,source_cached1,
    output wire [31:0] source_id0,source_id1,
    output wire [5:0] source_index0,source_index1
);
    (* ram_style="bram" *) reg [7:0] bitmap0[0:2303];
    (* ram_style="bram" *) reg [7:0] bitmap1[0:2303];
    reg reserved0,reserved1,source_valid0,source_valid1;
    reg [31:0] source_session0,source_session1;
    reg [5:0] source_cue0,source_cue1;
    wire [38:0] metadata0,metadata1;
    wire metadata_ready0,metadata_ready1;
    wire [32:0] release_message0,release_message1;
    assign free0=!reserved0 && !source_valid0 && !release_message0[0] && metadata_ready0;
    assign free1=!reserved1 && !source_valid1 && !release_message1[0] && metadata_ready1;
    assign any_reserved=reserved0 || reserved1;
    assign source_cached0=source_valid0;assign source_cached1=source_valid1;
    assign source_id0=source_session0;assign source_id1=source_session1;
    assign source_index0=source_cue0;assign source_index1=source_cue1;
    assign {valid0,session0,cue0}=metadata0;
    assign {valid1,session1,cue1}=metadata1;
    player_settings_cdc #(.WIDTH(39),.RESET_VALUE(39'd0)) bank0_metadata (
        .src_clk(write_clk),.src_rst(write_rst),.src_value({source_valid0,source_session0,source_cue0}),
        .dst_clk(pixel_clk),.dst_rst(pixel_rst),.dst_value(metadata0),.src_ready(metadata_ready0));
    player_settings_cdc #(.WIDTH(39),.RESET_VALUE(39'd0)) bank1_metadata (
        .src_clk(write_clk),.src_rst(write_rst),.src_value({source_valid1,source_session1,source_cue1}),
        .dst_clk(pixel_clk),.dst_rst(pixel_rst),.dst_value(metadata1),.src_ready(metadata_ready1));
    player_settings_cdc #(.WIDTH(33),.RESET_VALUE(33'd0)) bank0_release (
        .src_clk(pixel_clk),.src_rst(pixel_rst),.src_value({release_session0,release0}),
        .dst_clk(write_clk),.dst_rst(write_rst),.dst_value(release_message0));
    player_settings_cdc #(.WIDTH(33),.RESET_VALUE(33'd0)) bank1_release (
        .src_clk(pixel_clk),.src_rst(pixel_rst),.src_value({release_session1,release1}),
        .dst_clk(write_clk),.dst_rst(write_rst),.dst_value(release_message1));
    always @(posedge write_clk) begin
        if(write && !abort_write && write_address<2304) begin
            if(!write_bank && reserved0 && !source_valid0 && source_session0==publish_session)
                bitmap0[write_address]<=write_data;
            if(write_bank && reserved1 && !source_valid1 && source_session1==publish_session)
                bitmap1[write_address]<=write_data;
        end
    end
    // Keep each RAM read port unconditional so TD can infer dual-clock BRAM.
    reg [7:0] pixel_byte0,pixel_byte1;
    reg pixel_bank_q,pixel_address_valid_q;
    always @(posedge pixel_clk) begin
        pixel_byte0<=bitmap0[pixel_address];
        pixel_byte1<=bitmap1[pixel_address];
        pixel_bank_q<=pixel_bank;
        pixel_address_valid_q<=pixel_address<2304;
    end
    assign pixel_byte=!pixel_address_valid_q ? 8'd0 : pixel_bank_q ? pixel_byte1 : pixel_byte0;
    always @(posedge write_clk or posedge write_rst) begin
        if(write_rst) begin
            reserved0<=0;reserved1<=0;source_valid0<=0;source_valid1<=0;
            source_session0<=0;source_session1<=0;source_cue0<=0;source_cue1<=0;ownership_error<=0;
        end else begin
            if(release_message0[0] && release_message0[32:1]==source_session0) source_valid0<=0;
            if(release_message1[0] && release_message1[32:1]==source_session1) source_valid1<=0;
            if(abort_write) begin reserved0<=0;reserved1<=0;end
            else begin
                if(reserve) begin
                    if(!write_bank && free0) begin reserved0<=1;source_session0<=publish_session;end
                    else if(write_bank && free1) begin reserved1<=1;source_session1<=publish_session;end
                    else ownership_error<=1;
                end
                if(write && (write_address>=2304 ||
                    (write_bank ? !reserved1 || source_valid1 || source_session1!=publish_session :
                                  !reserved0 || source_valid0 || source_session0!=publish_session))) ownership_error<=1;
                if(publish) begin
                    if(!write_bank && reserved0 && !source_valid0 && source_session0==publish_session) begin
                        reserved0<=0;source_cue0<=publish_cue;source_valid0<=1;
                    end else if(write_bank && reserved1 && !source_valid1 && source_session1==publish_session) begin
                        reserved1<=0;source_cue1<=publish_cue;source_valid1<=1;
                    end else ownership_error<=1;
                end
                if(discard) begin if(write_bank)reserved1<=0;else reserved0<=0;end
            end
        end
    end
endmodule
