`timescale 1ns/1ps

// FAT32 byte stream to the same 48 kHz PCM contract as wav_stream_player.
// The file streamer pauses before a DATA sector when this FIFO cannot hold it.
module pcm_file_fifo #(
    parameter integer ADDR_WIDTH=9,
    parameter integer SAMPLES_PER_SECTOR=256,
    parameter integer ENABLE_STARTED_EVENT=0,
    parameter integer ENABLE_AUDIO_PROGRESS=0
) (
    input  wire        wr_clk,wr_rst_n,
    input  wire        file_valid,
    input  wire [7:0]  file_byte,
    input  wire        file_done,
    input  wire [7:0]  file_error,
    output wire        sector_allow,
    input  wire        rd_clk,rd_rst_n,
    input  wire        sample_tick,sample_ready,
    output reg signed [15:0] sample_out,
    output reg         sample_valid,
    output wire        stream_active,stream_end,
    output reg         stream_error,
    output reg         sample_started,
    output reg [31:0] played_samples
);
    (* ram_style="block" *) reg [15:0] buffer [0:(1<<ADDR_WIDTH)-1];
    reg [ADDR_WIDTH:0] wr_ptr,rd_ptr,wr_gray,rd_gray;
    reg [ADDR_WIDTH:0] wr_sync1,wr_sync2,rd_sync1,rd_sync2;
    reg [7:0] low_byte;
    reg low_pending,finished;
    reg real_sample_q,started_q;
    reg [2:0] finished_sync;
    reg primed,read_pending;
    reg [15:0] ram_sample;
    wire [ADDR_WIDTH:0] level_wr=wr_ptr-from_gray(rd_sync2);
    wire [ADDR_WIDTH:0] level_rd=from_gray(wr_sync2)-rd_ptr;
    wire can_sample=!sample_valid || sample_ready;
    wire take_sample=sample_tick && can_sample && !read_pending &&
                     primed && level_rd!=0;

    function [ADDR_WIDTH:0] to_gray;
        input [ADDR_WIDTH:0] binary;
        begin to_gray=binary^(binary>>1);end
    endfunction
    function [ADDR_WIDTH:0] from_gray;
        input [ADDR_WIDTH:0] gray;
        integer i;
        begin
            from_gray[ADDR_WIDTH]=gray[ADDR_WIDTH];
            for(i=ADDR_WIDTH-1;i>=0;i=i-1)
                from_gray[i]=from_gray[i+1]^gray[i];
        end
    endfunction

    assign sector_allow=level_wr <= (1<<ADDR_WIDTH)-SAMPLES_PER_SECTOR;
    assign stream_end=finished_sync[2] && level_rd==0 &&
                      !read_pending && !sample_valid;
    assign stream_active=primed && !stream_end;

    // Independent synchronous BRAM ports. Neither port has reset logic.
    always @(posedge wr_clk)
        if(file_valid && low_pending)
            buffer[wr_ptr[ADDR_WIDTH-1:0]]<={file_byte,low_byte};
    always @(posedge rd_clk)
        if(take_sample)
            ram_sample<=buffer[rd_ptr[ADDR_WIDTH-1:0]];

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n) begin
            wr_ptr<=0;wr_gray<=0;rd_sync1<=0;rd_sync2<=0;
            low_byte<=0;low_pending<=0;finished<=0;stream_error<=0;
        end else begin
            rd_sync1<=rd_gray;rd_sync2<=rd_sync1;
            if(file_valid) begin
                low_pending<=!low_pending;
                if(!low_pending) low_byte<=file_byte;
                else begin
                    wr_ptr<=wr_ptr+1'b1;
                    wr_gray<=to_gray(wr_ptr+1'b1);
                end
            end
            if(file_done) begin
                finished<=1;
                if(file_error!=0 || low_pending) stream_error<=1;
            end
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if(!rd_rst_n) begin
            rd_ptr<=0;rd_gray<=0;wr_sync1<=0;wr_sync2<=0;
            finished_sync<=0;primed<=0;read_pending<=0;
            sample_out<=0;sample_valid<=0;sample_started<=0;real_sample_q<=0;started_q<=0;played_samples<=0;
        end else begin
            sample_started<=0;
            if(ENABLE_AUDIO_PROGRESS!=0 && sample_valid && sample_ready && real_sample_q)
                played_samples<=played_samples+1'b1;
            if(ENABLE_STARTED_EVENT!=0 && sample_valid && sample_ready && real_sample_q && !started_q) begin
                sample_started<=1;started_q<=1;
            end
            wr_sync1<=wr_gray;wr_sync2<=wr_sync1;
            finished_sync<={finished_sync[1:0],finished};
            if(!primed && (level_rd>=SAMPLES_PER_SECTOR || finished_sync[2]))
                primed<=1;
            if(sample_valid && sample_ready) sample_valid<=0;
            if(read_pending) begin
                sample_out<=ram_sample;sample_valid<=1;read_pending<=0;
                if(ENABLE_STARTED_EVENT!=0 || ENABLE_AUDIO_PROGRESS!=0) real_sample_q<=1;
            end else if(take_sample) begin
                rd_ptr<=rd_ptr+1'b1;rd_gray<=to_gray(rd_ptr+1'b1);
                read_pending<=1;
            end else if(sample_tick && can_sample && !finished_sync[2]) begin
                sample_out<=0;sample_valid<=1;
                real_sample_q<=0;
            end
        end
    end
endmodule
