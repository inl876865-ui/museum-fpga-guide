`timescale 1ns/1ps

// Read one ordered pixel stream from either one bank or two bank segments.
// During wipe, each row reads new-bank pixels before the boundary and
// old-bank pixels after it. The existing asynchronous FIFO is unchanged.
module frame_fifo_read_wipe #(
    parameter integer ADDR_BITS = 21,
    parameter integer BURST_SIZE = 256,
    parameter integer FIFO_DEPTH = 512,
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480
) (
    input  wire                 rst,
    input  wire                 mem_clk,
    input  wire                 Sdr_init_done,
    input  wire                 App_wr_busy,
    output wire                 O_rd_busy,
    output wire                 App_rd_en,
    output wire [ADDR_BITS-1:0] App_rd_addr,
    input  wire                 read_req,
    output reg                  read_req_ack,
    output wire                 read_finish,
    input  wire [1:0]           read_addr_index,
    input  wire [ADDR_BITS-1:0] read_len,
    input  wire                 wipe_active,
    input  wire [1:0]           wipe_old_index,
    input  wire [1:0]           wipe_new_index,
    input  wire [9:0]           wipe_boundary,
    output reg                  fifo_aclr,
    input  wire [9:0]           wrusedw
);
    localparam [ADDR_BITS-1:0] FRAME_WORDS = FRAME_WIDTH * FRAME_HEIGHT;
    localparam [2:0] S_IDLE=0, S_ACK=1, S_CHECK=2,
                     S_BURST=3, S_DRAIN=4, S_DONE=5;
    reg [2:0] state;
    (* async_reg = "true" *) reg [2:0] req_sync;
    reg [ADDR_BITS-1:0] len_sync0, len_sync1, frame_len;
    reg [1:0] index_sync0, index_sync1, frame_index;
    reg wipe_sync0, wipe_sync1, frame_wipe;
    reg [1:0] old_sync0, old_sync1, frame_old;
    reg [1:0] new_sync0, new_sync1, frame_new;
    reg [9:0] boundary_sync0, boundary_sync1, frame_boundary;
    reg [ADDR_BITS-1:0] issued, row_offset;
    reg [9:0] col;
    reg [8:0] burst_target, burst_sent;
    reg [3:0] drain_count;
    reg read_command, read_enable_q;
    reg [ADDR_BITS-1:0] read_address_q;

    function [ADDR_BITS-1:0] bank_base;
        input [1:0] bank;
        begin
            case (bank)
                2'd0: bank_base = 0;
                2'd1: bank_base = FRAME_WORDS;
                2'd2: bank_base = FRAME_WORDS * 2;
                default: bank_base = FRAME_WORDS * 3;
            endcase
        end
    endfunction

    wire [9:0] boundary = frame_boundary > FRAME_WIDTH ?
                          FRAME_WIDTH : frame_boundary;
    wire [1:0] source_bank = frame_wipe ?
                             (col < boundary ? frame_new : frame_old) :
                             frame_index;
    wire [ADDR_BITS-1:0] remaining = frame_len - issued;
    wire [9:0] segment_remaining = col < boundary ?
                                   boundary - col : FRAME_WIDTH - col;
    wire [ADDR_BITS-1:0] segment_address = bank_base(source_bank) + row_offset + col;
    // The SDRAM address layout has an eight-bit physical column.
    wire [8:0] page_remaining = 9'd256 - {1'b0, segment_address[7:0]};
    reg [ADDR_BITS-1:0] next_burst;
    always @* begin
        next_burst = remaining;
        if (next_burst > BURST_SIZE)
            next_burst = BURST_SIZE;
        if (frame_wipe && next_burst > segment_remaining)
            next_burst = segment_remaining;
        if (frame_wipe && next_burst > page_remaining)
            next_burst = page_remaining;
    end
    wire can_burst = state == S_CHECK && issued < frame_len &&
                     wrusedw < FIFO_DEPTH - BURST_SIZE && !App_wr_busy;
    // Match the verified reader: register command enable/address, retain
    // ownership through the return delay, then use a separate burst-end cycle.
    assign O_rd_busy = state == S_BURST;
    assign App_rd_en = read_enable_q;
    assign App_rd_addr = read_address_q;
    assign read_finish = state == S_DONE;

    always @(posedge mem_clk or posedge rst) begin
        if (rst) begin
            req_sync <= 0;
            len_sync0 <= 0; len_sync1 <= 0;
            index_sync0 <= 0; index_sync1 <= 0;
            wipe_sync0 <= 0; wipe_sync1 <= 0;
            old_sync0 <= 0; old_sync1 <= 0;
            new_sync0 <= 0; new_sync1 <= 0;
            boundary_sync0 <= 0; boundary_sync1 <= 0;
        end else begin
            req_sync <= {req_sync[1:0], read_req};
            len_sync0 <= read_len; len_sync1 <= len_sync0;
            index_sync0 <= read_addr_index; index_sync1 <= index_sync0;
            wipe_sync0 <= wipe_active; wipe_sync1 <= wipe_sync0;
            old_sync0 <= wipe_old_index; old_sync1 <= old_sync0;
            new_sync0 <= wipe_new_index; new_sync1 <= new_sync0;
            boundary_sync0 <= wipe_boundary; boundary_sync1 <= boundary_sync0;
        end
    end

    always @(posedge mem_clk or posedge rst) begin
        if (rst) begin
            burst_sent <= 0;
            read_enable_q <= 0;
            read_address_q <= 0;
            drain_count <= 0;
        end else begin
            if (state == S_CHECK) burst_sent <= 0;
            else if (App_rd_en) burst_sent <= burst_sent + 1'b1;
            read_enable_q <= read_command && burst_sent + App_rd_en < burst_target;
            if (state == S_ACK)
                read_address_q <= bank_base(wipe_sync1 ?
                    (boundary_sync1 == 0 ? old_sync1 : new_sync1) : index_sync1);
            else if (App_rd_en)
                read_address_q <= read_address_q + 1'b1;
            else if (state == S_CHECK && frame_wipe)
                read_address_q <= segment_address;
            if (App_rd_en) drain_count <= 0;
            else if (drain_count < 10) drain_count <= drain_count + 1'b1;
        end
    end

    always @(posedge mem_clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            read_req_ack <= 0;
            fifo_aclr <= 0;
            frame_len <= 0;
            frame_index <= 0;
            frame_wipe <= 0;
            frame_old <= 0;
            frame_new <= 0;
            frame_boundary <= 0;
            issued <= 0;
            row_offset <= 0;
            col <= 0;
            burst_target <= 0;
            read_command <= 0;
        end else begin
            if (App_rd_en) begin
                issued <= issued + 1'b1;
                if (col == FRAME_WIDTH - 1) begin
                    col <= 0;
                    row_offset <= row_offset + FRAME_WIDTH;
                end else col <= col + 1'b1;
            end
            case (state)
                S_IDLE: begin
                    read_req_ack <= 0;
                    if (req_sync[2] && Sdr_init_done) state <= S_ACK;
                end
                S_ACK: begin
                    read_req_ack <= 1;
                    fifo_aclr <= 1;
                    frame_len <= len_sync1;
                    frame_index <= index_sync1;
                    frame_wipe <= wipe_sync1;
                    frame_old <= old_sync1;
                    frame_new <= new_sync1;
                    frame_boundary <= boundary_sync1;
                    issued <= 0;
                    row_offset <= 0;
                    col <= 0;
                    if (!req_sync[2]) begin
                        read_req_ack <= 0;
                        fifo_aclr <= 0;
                        state <= S_CHECK;
                    end
                end
                S_CHECK: begin
                    if (req_sync[2])
                        state <= S_ACK;
                    else if (can_burst) begin
                        burst_target <= next_burst[8:0];
                        read_command <= 1;
                        state <= S_BURST;
                    end
                end
                S_BURST: begin
                    if (burst_sent >= burst_target && drain_count == 10) begin
                        read_command <= 0;
                        state <= S_DRAIN;
                    end
                end
                S_DRAIN: begin
                    if (req_sync[2]) state <= S_ACK;
                    else if (issued < frame_len) state <= S_CHECK;
                    else state <= S_DONE;
                end
                S_DONE: state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
