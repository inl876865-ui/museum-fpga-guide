`timescale 1ns/1ps

// CAP-only copy: original PCM/BMP/TRANS streamer and public interface stay intact.
// FAT checks are retained; addresses share one adder and shift one bit per clock.
module caption_file_streamer #(
    parameter integer MAX_VISITED_CLUSTERS = 512,
    parameter integer FILE_SIZE_BITS = 18
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        file_start,
    input  wire        data_sector_allow,
    input  wire [31:0] first_cluster,
    input  wire [31:0] file_size,
    input  wire [7:0]  sectors_per_cluster,
    input  wire [31:0] fat_start_lba,
    input  wire [31:0] data_start_lba,
    input  wire [31:0] max_cluster,
    output wire        file_busy,
    output reg         file_done,
    output reg         file_valid,
    output reg  [7:0]  file_byte,
    output reg  [31:0] file_byte_offset,
    output reg  [7:0]  fs_error,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_busy,
    input  wire        sector_valid,
    input  wire [7:0]  sector_byte,
    input  wire [8:0]  sector_byte_index,
    input  wire        sector_done,
    input  wire [7:0]  sector_error
);
    localparam ERR_NONE              = 8'h00;
    localparam ERR_SECTOR            = 8'h10;
    localparam ERR_FAT_LOOP          = 8'h23;
    localparam ERR_CLUSTER_RANGE     = 8'h24;
    localparam ERR_EARLY_EOF         = 8'h25;
    localparam ERR_VISITED_EXHAUSTED = 8'h26;

    localparam ST_IDLE       = 4'd0;
    localparam ST_DATA_REQ   = 4'd1;
    localparam ST_DATA_WAIT  = 4'd2;
    localparam ST_FAT_REQ    = 4'd3;
    localparam ST_FAT_WAIT   = 4'd4;
    localparam ST_FAT_PARSE  = 4'd5;
    localparam ST_FINISH     = 4'd7;

    localparam integer CHAIN_COUNT_WIDTH = $clog2(MAX_VISITED_CLUSTERS + 1);

    localparam ST_ADDR_SUB=4'd8, ST_ADDR_SHIFT=4'd9, ST_ADDR_ADD=4'd10;
    localparam ST_DATA_CHECK=4'd11, ST_DATA_NEXT_ADDR=4'd12, ST_DATA_FAT_ADDR=4'd13;
    reg [31:0] address_offset;
    reg [2:0] cluster_shift,shift_remaining;
    reg [31:0] address_left,address_right;
    wire [31:0] address_sum=address_left+address_right;
    always @* begin
        address_left=sector_lba;address_right=32'd1;
        case(state)
            ST_ADDR_SUB:begin address_left=current_cluster;address_right=32'hfffffffe;end
            ST_ADDR_ADD:begin address_left=data_start_lba;address_right=address_offset;end
            ST_DATA_FAT_ADDR:begin address_left=fat_start_lba;address_right={7'd0,current_cluster[31:7]};end
            default:begin end
        endcase
    end
    function [2:0] spc_shift;
        input [7:0] n;
        begin
            case(n)
                2:spc_shift=1;4:spc_shift=2;8:spc_shift=3;16:spc_shift=4;
                32:spc_shift=5;64:spc_shift=6;128:spc_shift=7;default:spc_shift=0;
            endcase
        end
    endfunction
    reg [3:0] state;
    reg [31:0] current_cluster;
    reg [31:0] next_cluster;
    reg [FILE_SIZE_BITS-1:0] remaining_bytes;
    reg [7:0] sector_in_cluster;
    reg [8:0] fat_entry_offset;
    reg [7:0] fat_byte0, fat_byte1, fat_byte2, fat_byte3;
    reg [CHAIN_COUNT_WIDTH-1:0] chain_count;
    reg final_chain_check;

    // Initial cluster and parsed FAT cluster are checked in exclusive states.
    // Keep full32 max/first operands and unchanged state/public timing.
    wire [31:0] range_cluster=state==ST_IDLE ? first_cluster :
        {4'd0,fat_byte3[3:0],fat_byte2,fat_byte1,fat_byte0};
    wire cluster_range_bad=range_cluster<2 || range_cluster>max_cluster;

    assign file_busy = (state != ST_IDLE);

    task finish_with_error;
        input [7:0] code;
        begin
            fs_error <= code;
            state <= ST_FINISH;
        end
    endtask

    task advance_to_next_cluster;
        input [31:0] cluster_value;
        begin
            chain_count <= chain_count + 1'b1;
            current_cluster <= cluster_value;
            state <= ST_ADDR_SUB;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            address_offset<=0;cluster_shift<=0;shift_remaining<=0;
            state <= ST_IDLE;
            file_done <= 1'b0;
            file_valid <= 1'b0;
            file_byte <= 8'd0;
            file_byte_offset <= 32'd0;
            fs_error <= ERR_NONE;
            sector_req <= 1'b0;
            sector_lba <= 32'd0;
            current_cluster <= 32'd0;
            next_cluster <= 32'd0;
            remaining_bytes <= 32'd0;
            sector_in_cluster <= 8'd0;
            fat_entry_offset <= 9'd0;
            fat_byte0 <= 8'd0;
            fat_byte1 <= 8'd0;
            fat_byte2 <= 8'd0;
            fat_byte3 <= 8'd0;
            chain_count <= 0;
            final_chain_check <= 1'b0;
        end else begin
            file_done <= 1'b0;
            file_valid <= 1'b0;
            sector_req <= 1'b0;

            if (state == ST_DATA_WAIT && sector_valid && remaining_bytes != 0) begin
                file_valid <= 1'b1;
                file_byte <= sector_byte;
                file_byte_offset <= file_size - remaining_bytes;
                remaining_bytes <= remaining_bytes - 1'b1;
            end

            if (state == ST_FAT_WAIT && sector_valid) begin
                if (sector_byte_index == fat_entry_offset)
                    fat_byte0 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 1'b1)
                    fat_byte1 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 2'd2)
                    fat_byte2 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 2'd3)
                    fat_byte3 <= sector_byte;
            end

            case (state)
                ST_IDLE: if (file_start) begin
                    // Capture private payload before validation; errors never consume it.
                    current_cluster <= first_cluster;
                    fs_error <= ERR_NONE;
                    file_byte_offset <= 32'd0;
                    remaining_bytes <= file_size;
                    cluster_shift<=spc_shift(sectors_per_cluster);
                    sector_in_cluster <= 8'd0;
                    chain_count <= 1;
                    final_chain_check <= 1'b0;
                    if(FILE_SIZE_BITS<32 && (file_size >> FILE_SIZE_BITS)!=0) begin
                        finish_with_error(ERR_VISITED_EXHAUSTED);
                    end else if (file_size == 0) begin
                        state <= ST_FINISH;
                    end else if (cluster_range_bad ||
                                 sectors_per_cluster == 0) begin
                        finish_with_error(ERR_CLUSTER_RANGE);
                    end else begin
                        state <= ST_ADDR_SUB;
                    end
                end
                ST_ADDR_SUB: begin address_offset<=address_sum;shift_remaining<=cluster_shift;state<=ST_ADDR_SHIFT;end
                ST_ADDR_SHIFT: begin
                    if(shift_remaining==0)state<=ST_ADDR_ADD;
                    else begin address_offset<={address_offset[30:0],1'b0};shift_remaining<=shift_remaining-1'b1;end
                end
                ST_ADDR_ADD: begin sector_lba<=address_sum;state<=ST_DATA_REQ;end
                ST_DATA_REQ: if (!sector_busy && data_sector_allow) begin
                    sector_req <= 1'b1;
                    state <= ST_DATA_WAIT;
                end
                ST_DATA_WAIT: if (sector_done) begin
                    if (sector_error != 0) begin
                        finish_with_error(ERR_SECTOR);
                    end else state <= ST_DATA_CHECK;
                end
                // Decide after the last byte has updated remaining_bytes.
                // This removes sector_valid/abort gating from the address path.
                ST_DATA_CHECK: begin
                    if (remaining_bytes == 0) begin
                        final_chain_check <= 1'b1;
                        sector_in_cluster <= 8'd0;
                        fat_entry_offset <= {current_cluster[6:0], 2'b00};
                        state <= ST_DATA_FAT_ADDR;
                    end else if (sector_in_cluster + 1'b1 < sectors_per_cluster) begin
                        sector_in_cluster <= sector_in_cluster + 1'b1;
                        state <= ST_DATA_NEXT_ADDR;
                    end else begin
                        sector_in_cluster <= 8'd0;
                        fat_entry_offset <= {current_cluster[6:0], 2'b00};
                        state <= ST_DATA_FAT_ADDR;
                    end
                end
                ST_DATA_NEXT_ADDR: begin
                    sector_lba <= address_sum;
                    state <= ST_DATA_REQ;
                end
                ST_DATA_FAT_ADDR: begin
                    sector_lba <= address_sum;
                    state <= ST_FAT_REQ;
                end
                ST_FAT_REQ: if (!sector_busy) begin
                    sector_req <= 1'b1;
                    state <= ST_FAT_WAIT;
                end
                ST_FAT_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else
                        state <= ST_FAT_PARSE;
                end
                ST_FAT_PARSE: begin
                    // Self-loop checks below still see the pre-edge cluster.
                    current_cluster <= {4'd0, fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0};
                    next_cluster <= {4'd0, fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0};
                    if (final_chain_check) begin
                        final_chain_check <= 1'b0;
                        if ({fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0} >= 28'hffffff8)
                            state <= ST_FINISH;
                        else if (cluster_range_bad)
                            finish_with_error(ERR_CLUSTER_RANGE);
                        else
                            finish_with_error(ERR_FAT_LOOP);
                    end else if ({fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0} >= 28'hffffff8) begin
                        finish_with_error(ERR_EARLY_EOF);
                    end else if (cluster_range_bad) begin
                        finish_with_error(ERR_CLUSTER_RANGE);
                    end else if (chain_count >= MAX_VISITED_CLUSTERS) begin
                        finish_with_error(ERR_VISITED_EXHAUSTED);
                    end else if ({4'd0, fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0} == current_cluster) begin
                        finish_with_error(ERR_FAT_LOOP);
                    end else begin
                        advance_to_next_cluster({4'd0, fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0});
                    end
                end
                ST_FINISH: begin
                    file_done <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
