`timescale 1ns/1ps

// Four fixed frame addresses, using the verified asynchronous write FIFO and
// SDRAM burst engine already present in this project.
module media_frame_loader #(
    parameter ADDR_BITS = 21,
    parameter BURST_SIZE = 128,
    parameter FRAME_WIDTH = 640,
    parameter FRAME_HEIGHT = 480
) (
    input  wire                  mem_clk,
    input  wire                  rst,
    input  wire                  Sdr_init_done,
    input  wire                  Sdr_init_ref_vld,
    input  wire                  Sdr_busy,
    input  wire                  App_rd_busy,
    output wire                  App_wr_busy,
    output wire                  App_wr_en,
    output wire [ADDR_BITS-1:0]  App_wr_addr,
    output wire [31:0]           App_wr_din,
    output wire [3:0]            App_wr_dm,
    input  wire                  write_clk,
    input  wire                  write_req,
    output wire                  write_req_ack,
    output wire                  write_finish,
    input  wire [1:0]            write_addr_index,
    input  wire [ADDR_BITS-1:0]  write_len,
    input  wire                  write_en,
    input  wire [31:0]           write_data,
    output wire                  pending,
    output wire                  write_ready,
    output reg                   fifo_overflow
);
    localparam [ADDR_BITS-1:0] FRAME_WORDS = FRAME_WIDTH * FRAME_HEIGHT;
    localparam [ADDR_BITS-1:0] BANK2_BASE = FRAME_WIDTH * FRAME_HEIGHT * 2;
    localparam [ADDR_BITS-1:0] BANK3_BASE = FRAME_WIDTH * FRAME_HEIGHT * 3;
    wire fifo_reset;
    wire fifo_full;
    wire [8:0] fifo_rdusedw;
    assign App_wr_dm = 4'b0000;
    // rst is released by the memory clock. Qualify release separately for
    // this write-clock status register; FIFO data and the burst engine stay
    // on their existing reset paths.
    (* async_reg="true" *) reg [1:0] write_reset_sync=2'b11;
    wire write_reset_request=rst || fifo_reset;
    assign write_ready=!write_reset_sync[1] && !fifo_full;
    always @(posedge write_clk or posedge write_reset_request) begin
        if(write_reset_request) write_reset_sync<=2'b11;
        else write_reset_sync<={write_reset_sync[0],1'b0};
    end
    always @(posedge write_clk or posedge write_reset_sync[1]) begin
        if (write_reset_sync[1]) fifo_overflow <= 1'b0;
        else fifo_overflow <= write_en && fifo_full;
    end

    wfifo_32_32_512 u_write_fifo (
        .clkw(write_clk), .clkr(mem_clk), .rst(fifo_reset),
        .we(write_en), .di(write_data),
        .re(App_wr_en), .dout(App_wr_din),
        .full_flag(fifo_full), .empty_flag(),
        .wrusedw(), .rdusedw(fifo_rdusedw)
    );

    frame_fifo_write #(
        .ADDR_BITS(ADDR_BITS), .BURST_SIZE(BURST_SIZE),
        .WRITE_V_FLIP(1), .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) u_write_engine (
        .rst(rst), .mem_clk(mem_clk),
        .Sdr_init_done(Sdr_init_done),
        .Sdr_init_ref_vld(Sdr_init_ref_vld), .Sdr_busy(Sdr_busy),
        .App_rd_busy(App_rd_busy), .O_wr_busy(App_wr_busy),
        .App_wr_en(App_wr_en), .App_wr_addr(App_wr_addr),
        .write_req(write_req), .write_req_ack(write_req_ack),
        .write_finish(write_finish),
        .write_addr_0({ADDR_BITS{1'b0}}),
        .write_addr_1(FRAME_WORDS),
        .write_addr_2(BANK2_BASE),
        .write_addr_3(BANK3_BASE),
        .write_addr_index(write_addr_index), .write_len(write_len),
        .pending(pending),.fifo_aclr(fifo_reset), .rdusedw({1'b0, fifo_rdusedw})
    );
endmodule
