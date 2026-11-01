`timescale 1ns/1ps

// Read one of four resident frames. The existing burst engine and asynchronous
// FIFO preserve the verified SDRAM-to-pixel timing and 32-bit RGB word layout.
module media_frame_reader #(
    parameter ADDR_BITS = 21,
    parameter BURST_SIZE = 256,
    parameter FRAME_WIDTH = 640,
    parameter FRAME_HEIGHT = 480,
    parameter ENABLE_WIPE = 0,
    parameter ENABLE_DIAGONAL_TRANSITION = 0
) (
    input  wire                  mem_clk,
    input  wire                  rst,
    input  wire                  Sdr_init_done,
    input  wire                  Sdr_init_ref_vld,
    input  wire                  Sdr_busy,
    input  wire                  Sdr_rd_en,
    input  wire [31:0]           Sdr_rd_dout,
    input  wire                  App_wr_busy,
    output wire                  App_rd_busy,
    output wire                  App_rd_en,
    output wire [ADDR_BITS-1:0]  App_rd_addr,
    input  wire                  read_clk,
    input  wire                  read_req,
    output wire                  read_req_ack,
    output wire                  read_finish,
    input  wire [1:0]            read_addr_index,
    input  wire [ADDR_BITS-1:0]  read_len,
    input wire diagonal_active,
    input wire [1:0] diagonal_old_index,diagonal_new_index,
    input wire [6:0] diagonal_shift,
    input  wire                  wipe_active,
    input  wire [1:0]            wipe_old_index,
    input  wire [1:0]            wipe_new_index,
    input  wire [9:0]            wipe_boundary,
    input  wire                  read_en,
    output wire [31:0]           read_data,
    output reg                   underflow,
    output wire                  pending,
    output reg                   fifo_overflow
);
    localparam [ADDR_BITS-1:0] FRAME_WORDS = FRAME_WIDTH * FRAME_HEIGHT;
    localparam [ADDR_BITS-1:0] BANK2_BASE = FRAME_WIDTH * FRAME_HEIGHT * 2;
    localparam [ADDR_BITS-1:0] BANK3_BASE = FRAME_WIDTH * FRAME_HEIGHT * 3;
    wire fifo_reset;
    wire fifo_empty;
    wire fifo_full;
    wire fifo_write;
    wire [8:0] fifo_wrusedw;
    (* async_reg = "true" *) reg [1:0] read_req_sync;
    reg read_req_seen;

    always @(posedge read_clk or posedge rst) begin
        if (rst)
            underflow <= 1'b0;
        else if (read_req)
            underflow <= 1'b0;
        else if (read_en && fifo_empty)
            underflow <= 1'b1;
    end
    always @(posedge mem_clk or posedge rst) begin
        if (rst) begin
            fifo_overflow <= 1'b0;
            read_req_sync <= 2'b00;
            read_req_seen <= 1'b0;
        end else begin
            read_req_sync <= {read_req_sync[0], read_req};
            read_req_seen <= read_req_sync[1];
            if (fifo_write && fifo_full)
                fifo_overflow <= 1'b1;
            else if (read_req_sync[1] && !read_req_seen)
                fifo_overflow <= 1'b0;
        end
    end

    rfifo_32_32_512 u_read_fifo (
        .clkw(mem_clk), .clkr(read_clk), .rst(fifo_reset),
        .we(fifo_write), .di(Sdr_rd_dout),
        .re(read_en), .dout(read_data),
        .full_flag(fifo_full), .empty_flag(fifo_empty),
        .wrusedw(fifo_wrusedw), .rdusedw()
    );

    generate
        if(ENABLE_DIAGONAL_TRANSITION!=0) begin : g_diagonal_reader
            frame_fifo_read_diagonal #(.ADDR_BITS(ADDR_BITS),.BURST_SIZE(BURST_SIZE),
                .FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT)) u_read_engine (
                .rst(rst),.mem_clk(mem_clk),.read_clk(read_clk),.initialized(Sdr_init_done),
                .refresh_busy(Sdr_init_ref_vld),.controller_busy(Sdr_busy),.return_valid(Sdr_rd_en),
                .blocked(App_wr_busy),.read_req(read_req),.read_req_ack(read_req_ack),
                .read_index(read_addr_index),.old_index(diagonal_old_index),.new_index(diagonal_new_index),
                .diagonal_active(diagonal_active),.diagonal_shift(diagonal_shift),.fifo_used(fifo_wrusedw),
                .fifo_clear(fifo_reset),.pending(pending),.busy(App_rd_busy),.app_read(App_rd_en),
                .read_finish(read_finish),.fifo_write(fifo_write),.app_address(App_rd_addr));
        end else if (ENABLE_WIPE == 0) begin : g_original_reader
            assign fifo_write=Sdr_rd_en;
            frame_fifo_read #(
                .ADDR_BITS(ADDR_BITS), .BURST_SIZE(BURST_SIZE)
            ) u_read_engine (
                .rst(rst), .mem_clk(mem_clk),
                .Sdr_init_done(Sdr_init_done),
                .Sdr_init_ref_vld(Sdr_init_ref_vld), .Sdr_busy(Sdr_busy),
                .Sdr_rd_en(Sdr_rd_en),
                .App_wr_busy(App_wr_busy), .O_rd_busy(App_rd_busy),
                .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr),
                .read_req(read_req), .read_req_ack(read_req_ack),
                .read_finish(read_finish),
                .read_addr_0({ADDR_BITS{1'b0}}),
                .read_addr_1(FRAME_WORDS),
                .read_addr_2(BANK2_BASE),
                .read_addr_3(BANK3_BASE),
                .read_addr_index(read_addr_index), .read_len(read_len),
                .pending(pending),.fifo_aclr(fifo_reset), .wrusedw({1'b0, fifo_wrusedw})
            );
        end else begin : g_wipe_reader
            assign fifo_write=Sdr_rd_en;
            assign pending=1'b0;
            frame_fifo_read_wipe #(
                .ADDR_BITS(ADDR_BITS), .BURST_SIZE(BURST_SIZE),
                .FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT)
            ) u_read_engine (
                .rst(rst), .mem_clk(mem_clk), .Sdr_init_done(Sdr_init_done),
                .App_wr_busy(App_wr_busy), .O_rd_busy(App_rd_busy),
                .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr),
                .read_req(read_req), .read_req_ack(read_req_ack),
                .read_finish(read_finish),
                .read_addr_index(read_addr_index), .read_len(read_len),
                .wipe_active(wipe_active),
                .wipe_old_index(wipe_old_index),
                .wipe_new_index(wipe_new_index),
                .wipe_boundary(wipe_boundary),
                .fifo_aclr(fifo_reset), .wrusedw({1'b0, fifo_wrusedw})
            );
        end
    endgenerate
endmodule
