`timescale 1ns/1ps
// Course PCM sector player, corrected transport, CDC and synchronous RAM.
module wav_stream_player #(
    parameter integer ADDR_WIDTH = 9,          // 512 x 16-bit = 1 KB
    parameter integer SAMPLES_PER_SECTOR = 256 // 512 bytes / 2
) (
    // write side: mem_clk domain (SD SPI engine clock)
    input  wire        wr_clk,
    input  wire        wr_rst_n,
    input  wire        play_enable,        // level: stream active
    input  wire [31:0] start_lba,          // first data sector (after WAV header)
    input  wire [31:0] total_sectors,      // audio data extent in sectors
    output wire        sd_req,             // request a sector read
    output reg  [31:0] sd_lba,
    input  wire        sd_busy,
    input  wire        sd_valid,           // one byte per valid pulse
    input  wire [7:0]  sd_byte,
    input  wire [8:0]  sd_byte_index,      // 0..511 within sector
    input  wire        sd_done,
    input  wire [7:0]  sd_error,

    // read side: pixel_clk domain (audio chain clock)
    input  wire        rd_clk,
    input  wire        rd_rst_n,
    input  wire        sample_tick,        // ~48 kHz pulse: consume one sample
    output reg  signed [15:0] sample_out,
    output reg         sample_valid,
    input  wire        sample_ready,       // from downstream (always 1 in our chain)

    // status (read side)
    output reg  [31:0] sample_counter,     // samples consumed (for OSD)
    output wire        stream_active,      // play_enable && not ended
    output wire        stream_end,         // all data consumed
    output wire        buffer_low          // < 25% remaining (for OSD/status)
);
    // One extra pointer bit distinguishes full from empty after wrap.
    (* ram_style = "block" *) reg [15:0] buffer [0:(1<<ADDR_WIDTH)-1];
    reg [ADDR_WIDTH:0] wr_ptr, rd_ptr, wr_gray, rd_gray;
    reg [ADDR_WIDTH:0] wr_gray_sync1, wr_gray_sync2;
    reg [ADDR_WIDTH:0] rd_gray_sync1, rd_gray_sync2;
    function [ADDR_WIDTH:0] to_gray;
        input [ADDR_WIDTH:0] b;
        begin to_gray=b^(b>>1); end
    endfunction
    function [ADDR_WIDTH:0] from_gray;
        input [ADDR_WIDTH:0] g;
        integer i;
        begin
            from_gray[ADDR_WIDTH]=g[ADDR_WIDTH];
            for(i=ADDR_WIDTH-1;i>=0;i=i-1)
                from_gray[i]=from_gray[i+1]^g[i];
        end
    endfunction
    wire [ADDR_WIDTH:0] level_wr=wr_ptr-from_gray(rd_gray_sync2);
    wire [ADDR_WIDTH:0] level_rd=from_gray(wr_gray_sync2)-rd_ptr;
    localparam [2:0] WS_IDLE=0, WS_REQ=1, WS_FILL=2, WS_END=4;
    reg [2:0] wstate;
    reg [31:0] sectors_read;
    reg [7:0] lo_byte;
    reg lo_pending;
    reg [9:0] byte_count;
    reg stream_error;
    wire space_for_sector=level_wr <= (1<<ADDR_WIDTH)-SAMPLES_PER_SECTOR;
    // LBA is registered BEFORE asserting req. Reserve space for a whole
    // unstoppable 512-byte transaction, not just for its first sample.
    assign sd_req=(wstate==WS_REQ) && play_enable && space_for_sector && !sd_busy;
    wire write_sample=(wstate==WS_FILL) && sd_valid && lo_pending && byte_count<512;
    // Separate synchronous RAM ports; neither port contains reset logic.
    always @(posedge wr_clk)
        if(write_sample) buffer[wr_ptr[ADDR_WIDTH-1:0]] <= {sd_byte,lo_byte};

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n) begin
            wstate<=WS_IDLE;sectors_read<=0;sd_lba<=0;
            wr_ptr<=0;wr_gray<=0;rd_gray_sync1<=0;rd_gray_sync2<=0;
            lo_byte<=0;lo_pending<=0;byte_count<=0;stream_error<=0;
        end else begin
            // Gray conversion/registration happens in the SOURCE domain.
            rd_gray_sync1<=rd_gray;rd_gray_sync2<=rd_gray_sync1;
            case(wstate)
                WS_IDLE: if(play_enable && total_sectors!=0) begin
                    sd_lba<=start_lba;wstate<=WS_REQ;
                end
                WS_REQ: if(!play_enable) wstate<=WS_END;
                    else if(sd_req) begin
                        wstate<=WS_FILL;byte_count<=0;lo_pending<=0;
                    end
                WS_FILL: begin
                    if(sd_valid && byte_count<512) begin
                        byte_count<=byte_count+1'b1;
                        lo_pending<=!lo_pending;
                        if(!lo_pending) lo_byte<=sd_byte;
                        if(write_sample) begin
                            wr_ptr<=wr_ptr+1'b1;
                            wr_gray<=to_gray(wr_ptr+1'b1);
                        end
                    end
                    if(sd_done) begin
                        if(sd_error!=0 || byte_count+(sd_valid?1:0)!=512) begin
                            stream_error<=1;wstate<=WS_END;
                        end else begin
                            sectors_read<=sectors_read+1'b1;
                            sd_lba<=sd_lba+1'b1;
                            if(sectors_read+1'b1>=total_sectors || !play_enable)
                                wstate<=WS_END;
                            else wstate<=WS_REQ;
                        end
                    end
                end
                // One-shot playback. A coordinated system reset restarts it.
                WS_END: ;
                default: wstate<=WS_IDLE;
            endcase
        end
    end

    reg [1:0] play_sync;
    reg [2:0] end_sync;
    reg primed, read_pending;
    reg [15:0] ram_sample;
    wire can_sample=!sample_valid || sample_ready;
    wire take_sample=play_sync[1] && sample_tick && can_sample &&
                     !read_pending && primed && level_rd!=0;
    always @(posedge rd_clk)
        if(take_sample) ram_sample<=buffer[rd_ptr[ADDR_WIDTH-1:0]];
    assign stream_end=end_sync[2] && level_rd==0 && !read_pending && !sample_valid;
    assign stream_active=play_sync[1] && !stream_end;
    assign buffer_low=level_rd<(1<<(ADDR_WIDTH-2));
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if(!rd_rst_n) begin
            rd_ptr<=0;rd_gray<=0;wr_gray_sync1<=0;wr_gray_sync2<=0;
            play_sync<=0;end_sync<=0;primed<=0;read_pending<=0;
            sample_valid<=0;sample_out<=0;sample_counter<=0;
        end else begin
            wr_gray_sync1<=wr_gray;wr_gray_sync2<=wr_gray_sync1;
            play_sync<={play_sync[0],play_enable};
            end_sync<={end_sync[1:0],wstate==WS_END};
            if(!primed && (level_rd>=SAMPLES_PER_SECTOR || end_sync[2])) primed<=1;
            if(sample_valid && sample_ready) sample_valid<=0;
            if(read_pending) begin
                sample_out<=ram_sample;sample_valid<=1;read_pending<=0;
            end else if(take_sample) begin
                rd_ptr<=rd_ptr+1'b1;rd_gray<=to_gray(rd_ptr+1'b1);
                read_pending<=1;sample_counter<=sample_counter+1'b1;
            end else if(play_sync[1] && sample_tick && can_sample && !end_sync[2]) begin
                // No pointer advance on underrun. Held samples survive stalls.
                sample_out<=0;sample_valid<=1;
            end
        end
    end
endmodule
