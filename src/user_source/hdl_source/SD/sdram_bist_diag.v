`timescale 1ns/1ps

// Temporary SDRAM address/data diagnostic for the four-frame layout.
module sdram_bist_diag #(
    parameter integer ADDR_WIDTH = 21,
    parameter integer IMAGE_WORDS = 307200,
    parameter integer INIT_WAIT_CYCLES = 4096,
    parameter integer WRITE_GAP_CYCLES = 32,
    parameter integer WRITE_SETTLE_CYCLES = 40000,
    parameter integer READ_GAP_CYCLES = 16,
    parameter integer READ_TIMEOUT_CYCLES = 4096,
    parameter integer RECHECK_INTERVAL_CYCLES = 40000000
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  init_done,
    input  wire                  rd_valid,
    input  wire [31:0]           rd_data,
    output reg                   wr_en,
    output reg  [ADDR_WIDTH-1:0] wr_addr,
    output reg  [31:0]           wr_data,
    output reg  [3:0]            wr_mask,
    output reg                   rd_en,
    output reg  [ADDR_WIDTH-1:0] rd_addr,
    output reg                   done,
    output reg                   error,
    output reg  [3:0]            error_bank
);
    localparam integer TESTS = 64;
    localparam [2:0] ST_WAIT = 3'd0;
    localparam [2:0] ST_WRITE = 3'd1;
    localparam [2:0] ST_WRITE_GAP = 3'd2;
    localparam [2:0] ST_SETTLE = 3'd3;
    localparam [2:0] ST_READ_REQ = 3'd4;
    localparam [2:0] ST_READ_WAIT = 3'd5;
    localparam [2:0] ST_READ_GAP = 3'd6;
    localparam [2:0] ST_PASS_WAIT = 3'd7;

    reg [2:0] state;
    reg [5:0] index;
    reg [31:0] wait_count;

    function [ADDR_WIDTH-1:0] test_address;
        input [5:0] n;
        reg [1:0] bank;
        reg [3:0] slot;
        begin
            bank = n[5:4];
            slot = n[3:0];
            case (slot)
                4'd0: test_address = bank * IMAGE_WORDS;
                4'd1: test_address = bank * IMAGE_WORDS + 21'd1;
                4'd2: test_address = bank * IMAGE_WORDS + 21'd255;
                4'd3: test_address = bank * IMAGE_WORDS + 21'd256;
                4'd4: test_address = bank * IMAGE_WORDS + 21'd511;
                4'd5: test_address = bank * IMAGE_WORDS + 21'd512;
                4'd6: test_address = bank * IMAGE_WORDS + 21'd1023;
                4'd7: test_address = bank * IMAGE_WORDS + 21'd1024;
                4'd8: test_address = bank * IMAGE_WORDS + 21'd8191;
                4'd9: test_address = bank * IMAGE_WORDS + 21'd8192;
                4'd10: test_address = bank * IMAGE_WORDS + 21'd65535;
                4'd11: test_address = bank * IMAGE_WORDS + 21'd65536;
                4'd12: test_address = bank * IMAGE_WORDS + 21'd131071;
                4'd13: test_address = bank * IMAGE_WORDS + 21'd131072;
                4'd14: test_address = bank * IMAGE_WORDS + 21'd262143;
                default: test_address = bank * IMAGE_WORDS + IMAGE_WORDS - 1;
            endcase
        end
    endfunction

    function [31:0] test_pattern;
        input [5:0] n;
        begin
            test_pattern = 32'hA55A0000 ^ (n * 32'h00010101);
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_WAIT;
            index <= 0;
            wait_count <= 0;
            wr_en <= 0;
            wr_addr <= 0;
            wr_data <= 0;
            wr_mask <= 0;
            rd_en <= 0;
            rd_addr <= 0;
            done <= 0;
            error <= 0;
            error_bank <= 0;
        end else begin
            wr_en <= 0;
            rd_en <= 0;
            if (state == ST_WAIT) begin
                if (!init_done)
                    wait_count <= 0;
                else if (wait_count == INIT_WAIT_CYCLES-1) begin
                    index <= 0;
                    wait_count <= 0;
                    state <= ST_WRITE;
                end else
                    wait_count <= wait_count + 1'b1;
            end else if (state == ST_WRITE) begin
                wr_en <= 1;
                wr_addr <= test_address(index);
                wr_data <= test_pattern(index);
                wr_mask <= 4'b0000;
                wait_count <= 0;
                state <= ST_WRITE_GAP;
            end else if (state == ST_WRITE_GAP) begin
                if (wait_count == WRITE_GAP_CYCLES-1) begin
                    wait_count <= 0;
                    if (index == TESTS-1) begin
                        index <= 0;
                        state <= ST_SETTLE;
                    end else begin
                        index <= index + 1'b1;
                        state <= ST_WRITE;
                    end
                end else
                    wait_count <= wait_count + 1'b1;
            end else if (state == ST_SETTLE) begin
                if (wait_count == WRITE_SETTLE_CYCLES-1) begin
                    wait_count <= 0;
                    state <= ST_READ_REQ;
                end else
                    wait_count <= wait_count + 1'b1;
            end else if (state == ST_READ_REQ) begin
                rd_en <= 1;
                rd_addr <= test_address(index);
                wait_count <= 0;
                state <= ST_READ_WAIT;
            end else if (state == ST_READ_WAIT) begin
                if (rd_valid) begin
                    if (rd_data != test_pattern(index)) begin
                        error <= 1'b1;
                        error_bank[index[5:4]] <= 1'b1;
                    end
                    if (index == TESTS-1)
                        done <= 1'b1;
                    wait_count <= 0;
                    state <= ST_READ_GAP;
                end else if (wait_count == READ_TIMEOUT_CYCLES-1) begin
                    error <= 1'b1;
                    error_bank[index[5:4]] <= 1'b1;
                    if (index == TESTS-1)
                        done <= 1'b1;
                    wait_count <= 0;
                    state <= ST_READ_GAP;
                end else
                    wait_count <= wait_count + 1'b1;
            end else if (state == ST_READ_GAP) begin
                if (wait_count == READ_GAP_CYCLES-1) begin
                    wait_count <= 0;
                    if (index == TESTS-1) begin
                        index <= 0;
                        state <= ST_PASS_WAIT;
                    end else begin
                        index <= index + 1'b1;
                        state <= ST_READ_REQ;
                    end
                end else
                    wait_count <= wait_count + 1'b1;
            end else if (state == ST_PASS_WAIT) begin
                if (wait_count == RECHECK_INTERVAL_CYCLES-1) begin
                    wait_count <= 0;
                    state <= ST_READ_REQ;
                end else
                    wait_count <= wait_count + 1'b1;
            end
        end
    end
endmodule
