module bmp_read #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer SD_READ_TIMEOUT_MS = 500,
    parameter [31:0] MAX_BMP_BYTES = 32'd16777216
)(
    input                       load_abort,
    output reg [2:0]            bmp_error,
    output reg                  load_error,
    output reg                  load_done,
    output reg                  scan_error,
    output reg                  scan_reject,
    output reg                  sd_recover,
    input                       clk,
    input                       rst,
    output                      ready,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [2:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [2:0]            scan_found_total,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input  [31:0]               load_sector,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data
);

localparam ST_IDLE      = 3'd0;
localparam ST_SCAN      = 3'd1;
localparam ST_LOAD_HDR  = 3'd2;
localparam ST_LOAD_WAIT = 3'd3;
localparam ST_LOAD_DATA = 3'd4;

reg [2:0]  state;
reg [9:0]  rd_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] width;
reg [31:0] height;
reg [15:0] bit_count;
reg [31:0] compression;
reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;

reg header_match;
wire bmp_data_valid;
wire [31:0] file_sector_count;
wire [31:0] next_scan_sector_if_match;
wire [31:0] next_scan_sector_if_miss;

reg [31:0] dib_size;
reg [15:0] planes;
reg [31:0] sd_timeout_cnt;
reg [9:0] sector_bytes;
reg [31:0] pixel_count;
localparam [2:0] ERR_NONE=0, ERR_HEADER=1, ERR_TIMEOUT=2, ERR_TRUNCATED=3;
localparam integer TIMEOUT_CYCLES = (CLK_FREQ_HZ / 1000) * SD_READ_TIMEOUT_MS;
wire [31:0] expected_pixels = {16'd0, bmp_width} * {16'd0, bmp_height};
reg [32:0] expected_end, dib_end, file_sectors_wide, scan_next_wide, load_end_sector;
reg [13:0] candidate_stride;
reg [26:0] candidate_bytes;
reg [32:0] candidate_end;
reg safe_file_extent;
// Pipeline header arithmetic while the remaining sector bytes arrive.
// Header fields end at byte 33; decisions are made only at sector end.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        expected_end<=0;dib_end<=0;file_sectors_wide<=0;scan_next_wide<=0;
        load_end_sector<=0;candidate_stride<=0;candidate_bytes<=0;
        candidate_end<=0;safe_file_extent<=0;
    end else begin
        expected_end <= {1'b0, pixel_offset} + ({1'b0, expected_pixels} * 3);
        dib_end <= {1'b0, dib_size} + 33'd14;
        file_sectors_wide <= ({1'b0, file_len} + 33'd511) >> 9;
        scan_next_wide <= {1'b0, scan_sector} + file_sectors_wide;
        load_end_sector <= {1'b0, load_sector_latched} + file_sectors_wide - 1'b1;
        candidate_stride <= (({1'b0,width[12:0]} * 14'd3) + 14'd3) & 14'h3ffc;
        candidate_bytes <= candidate_stride * height[12:0];
        candidate_end <= {1'b0, pixel_offset} + {6'd0, candidate_bytes};
        safe_file_extent <= header_0 == "B" && header_1 == "M" &&
    dib_size >= 40 && dib_end <= {1'b0, pixel_offset} && planes == 1 &&
    width > 0 && width <= 4096 && height > 0 && height <= 4096 &&
    bit_count == 24 && compression == 0 && pixel_offset >= 54 &&
    pixel_offset < file_len && file_len <= MAX_BMP_BYTES &&
    candidate_end <= {1'b0, file_len} && scan_next_wide > {1'b0, scan_sector} &&
    scan_next_wide <= ({1'b0, scan_max_sector} + 33'd1);
    end
end
wire pixel_emitted = state == ST_LOAD_DATA && bmp_data_valid && bmp_byte_idx == 2;
wire [31:0] pixels_at_end = pixel_count + (pixel_emitted ? 32'd1 : 32'd0);
wire [32:0] bytes_at_end = {1'b0, bmp_len_cnt} + (sd_sec_read_data_valid ? 33'd1 : 33'd0);
wire [10:0] sector_bytes_at_end = {1'b0, sector_bytes} + (sd_sec_read_data_valid ? 11'd1 : 11'd0);
wire timeout_now = state != ST_IDLE && sd_timeout_cnt >= TIMEOUT_CYCLES - 1;
wire stop_pixels = load_abort || timeout_now || !sd_init_done;

// A bounded timeout applies to each sector and to the write-request handshake.
// Ordinary byte progress does not extend it indefinitely.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        sd_timeout_cnt <= 0;
        sector_bytes <= 0;
        pixel_count <= 0;
    end else begin
        if (state == ST_IDLE || sd_sec_read_end ||
            (state == ST_LOAD_WAIT && write_req_ack))
            sd_timeout_cnt <= 0;
        else if (!timeout_now)
            sd_timeout_cnt <= sd_timeout_cnt + 1'b1;
        if (state == ST_IDLE || state == ST_LOAD_WAIT || sd_sec_read_end)
            sector_bytes <= 0;
        else if (sd_sec_read_data_valid && sector_bytes != 10'h3ff)
            sector_bytes <= sector_bytes + 1'b1;
        if (state != ST_LOAD_DATA)
            pixel_count <= 0;
        else if (pixel_emitted)
            pixel_count <= pixel_count + 1'b1;
    end
end

assign ready = (state == ST_IDLE);
always @(posedge clk or posedge rst) begin
    if (rst) header_match <= 1'b0;
    else header_match <= (header_0 == "B") &&
                      (header_1 == "M") &&
                      (width == {16'd0, bmp_width}) &&
                      (height == {16'd0, bmp_height}) &&
                      (bit_count    == 16'd24) &&
                      (compression  == 32'd0) &&
                      (dib_size >= 40) && (dib_end <= {1'b0, pixel_offset}) &&
                      (planes == 1) && (pixel_offset >= 54) &&
                      (pixel_offset < file_len) && (file_len <= MAX_BMP_BYTES) &&
                      (bmp_width != 0) && (bmp_height != 0) &&
                      (bmp_width[1:0] == 0) && // current no-padding RGB24 path
                      (expected_end <= {1'b0, file_len});
end
assign bmp_data_valid = (sd_sec_read_data_valid == 1'b1) &&
                        (bmp_len_cnt >= pixel_offset) &&
                        ({1'b0, bmp_len_cnt} < expected_end) && !stop_pixels;
assign file_sector_count = file_sectors_wide[31:0];
assign next_scan_sector_if_match = scan_next_wide[31:0];
assign next_scan_sector_if_miss  = scan_sector + 32'd1;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR)) begin
        if (sd_sec_read_end)
            rd_cnt <= 10'd0;
        else if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
        dib_size <= 0;
        planes <= 0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR)) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : header_0 <= sd_sec_read_data;
            10'd1 : header_1 <= sd_sec_read_data;

            10'd2 : file_len[7:0] <= sd_sec_read_data;
            10'd3 : file_len[15:8] <= sd_sec_read_data;
            10'd4 : file_len[23:16] <= sd_sec_read_data;
            10'd5 : file_len[31:24] <= sd_sec_read_data;

            10'd10: pixel_offset[7:0] <= sd_sec_read_data;
            10'd11: pixel_offset[15:8] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;

            10'd14: dib_size[7:0] <= sd_sec_read_data;
            10'd15: dib_size[15:8] <= sd_sec_read_data;
            10'd16: dib_size[23:16] <= sd_sec_read_data;
            10'd17: dib_size[31:24] <= sd_sec_read_data;
            10'd26: planes[7:0] <= sd_sec_read_data;
            10'd27: planes[15:8] <= sd_sec_read_data;
            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= sd_sec_read_data;
            10'd20: width[23:16] <= sd_sec_read_data;
            10'd21: width[31:24] <= sd_sec_read_data;

            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= sd_sec_read_data;
            10'd24: height[23:16] <= sd_sec_read_data;
            10'd25: height[31:24] <= sd_sec_read_data;

            10'd28: bit_count[7:0] <= sd_sec_read_data;
            10'd29: bit_count[15:8] <= sd_sec_read_data;

            10'd30: compression[7:0] <= sd_sec_read_data;
            10'd31: compression[15:8] <= sd_sec_read_data;
            10'd32: compression[23:16] <= sd_sec_read_data;
            10'd33: compression[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_byte_idx <= 2'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid)
            bmp_byte_idx <= (bmp_byte_idx == 2'd2) ? 2'd0 : (bmp_byte_idx + 2'd1);
    end else begin
        bmp_byte_idx <= 2'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid) begin
            case (bmp_byte_idx)
                2'd0: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[7:0]  <= sd_sec_read_data;
                end
                2'd1: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[15:8] <= sd_sec_read_data;
                end
                2'd2: begin
                    bmp_data_wr_en  <= 1'b1;
                    bmp_data[23:16] <= sd_sec_read_data;
                end
                default: begin
                    bmp_data_wr_en <= 1'b0;
                end
            endcase
        end else begin
            bmp_data_wr_en <= 1'b0;
        end
    end else begin
        bmp_data_wr_en <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_error <= ERR_NONE;
        load_error <= 0;
        load_done <= 0;
        scan_error <= 0;
        scan_reject <= 0;
        sd_recover <= 0;
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
    end else begin
        scan_found_valid <= 1'b0;
        load_error <= 1'b0;
        load_done <= 1'b0;
        scan_error <= 1'b0;
        scan_reject <= 1'b0;
        sd_recover <= 1'b0;
        if (load_abort || (state != ST_IDLE && (!sd_init_done || timeout_now))) begin
            state <= ST_IDLE;
            sd_sec_read <= 1'b0;
            write_req <= 1'b0;
            if (!load_abort) begin
                bmp_error <= ERR_TIMEOUT;
                sd_recover <= 1'b1;
                if (state == ST_SCAN) begin
                    scan_error <= 1'b1;
                    scan_done <= 1'b1;
                end else load_error <= 1'b1;
            end
        end else if (!sd_init_done) begin
            sd_sec_read <= 1'b0;
            write_req <= 1'b0;
        end else begin
        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    bmp_error <= ERR_NONE;
                    scan_done        <= 1'b0;
                    scan_found_total <= 3'd0;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= scan_start_sector;
                    state            <= ST_SCAN;
                end else if (load_start) begin
                    bmp_error <= ERR_NONE;
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    state               <= ST_LOAD_HDR;
                end
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;

                    if (sector_bytes_at_end != 512) begin
                        bmp_error <= ERR_TRUNCATED;
                        scan_error <= 1'b1;
                        scan_done <= 1'b1;
                        state <= ST_IDLE;
                        sd_recover <= 1'b1;
                    end else if (header_match && safe_file_extent) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 3'd1;

                        if ((scan_found_total + 3'd1 >= scan_target_count) || (next_scan_sector_if_match > scan_max_sector)) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end
                    end else begin
                        if (header_0 == "B" && header_1 == "M") begin
                            bmp_error <= ERR_HEADER;
                            scan_reject <= 1'b1;
                        end
                        if (scan_sector >= scan_max_sector ||
                            (safe_file_extent && scan_next_wide > {1'b0, scan_max_sector})) begin
                            scan_done <= 1'b1;
                            state <= ST_IDLE;
                        end else if (safe_file_extent) begin
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector <= next_scan_sector_if_match;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector <= next_scan_sector_if_miss;
                        end
                    end
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (sector_bytes_at_end != 512) begin
                        bmp_error <= ERR_TRUNCATED;
                        load_error <= 1'b1;
                        sd_recover <= 1'b1;
                        state <= ST_IDLE;
                    end else if (header_match && load_sector_latched >= scan_start_sector &&
                                 load_end_sector <= {1'b0, scan_max_sector}) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        bmp_error <= ERR_HEADER;
                        load_error <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_req_ack) begin
                    write_req <= 1'b0;
                    state     <= ST_LOAD_DATA;
                end
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (sector_bytes_at_end != 512) begin
                        bmp_error <= ERR_TRUNCATED;
                        load_error <= 1'b1;
                        sd_recover <= 1'b1;
                        state <= ST_IDLE;
                    end else if (bytes_at_end >= expected_end) begin
                        if (pixels_at_end != expected_pixels) begin
                            bmp_error <= ERR_TRUNCATED;
                            load_error <= 1'b1;
                        end else load_done <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end
                end
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
        end
    end
end

endmodule
