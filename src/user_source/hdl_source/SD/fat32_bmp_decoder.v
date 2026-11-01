`timescale 1ns/1ps
// Fixed bottom-up BMP24 contract; stream offsets include the entire file.
module fat32_bmp_decoder(
    input wire clk,rst,start,
    input wire [31:0] file_size,
    input wire [15:0] width_expected,height_expected,
    input wire valid,
    input wire [31:0] offset,
    input wire [7:0] data,
    input wire done,
    input wire [7:0] upstream_error,
    output reg pixel_valid,
    output reg [23:0] pixel,
    output reg complete,
    output reg [2:0] error
);
    reg [15:0] signature,planes,bpp;
    reg [31:0] declared_size,pixel_offset,dib,width,height,compression;
    // Existing header contract caps files at 16 MiB and width at 65535.
    // Include 16 MiB itself in byte counters; BMP24 pixels <= floor(16 MiB/3).
    // Largest padded row is 196608 bytes, so row position needs 18 bits.
    reg [24:0] expected_offset;
    reg [22:0] pixels;
    reg [17:0] row_byte;
    reg [1:0] phase;
    reg [7:0] blue,green;
    reg accepted,header_fields_ok;
    reg [31:0] pixel_start_offset;
    reg pixel_started;
    reg [24:0] pixel_bytes_remaining;
    // Saturating local header position avoids 32-bit offset fanout to every field.
    reg [5:0] header_position;
    wire [31:0] row_bytes={16'd0,width_expected}*3;
    wire [31:0] stride=(row_bytes+3)&32'hfffffffc;
    wire [63:0] image_bytes={32'd0,stride}*height_expected;
    wire [63:0] image_end={32'd0,pixel_offset}+image_bytes;
    // Stored header fields finish at byte 33, before the byte-53 decision.
    wire header_ok=header_fields_ok &&
        width=={16'd0,width_expected} && height=={16'd0,height_expected} &&
        image_end<=declared_size && declared_size<=file_size &&
        file_size<=16777216 && file_size>=54;
    always @(posedge clk) begin
        if(rst || start) begin
            header_position<=0;header_fields_ok<=0;pixel_start_offset<=0;
            signature<=0;planes<=0;bpp<=0;declared_size<=0;pixel_offset<=0;
            dib<=0;width<=0;height<=0;compression<=0;expected_offset<=0;
            pixels<=0;row_byte<=0;phase<=0;blue<=0;green<=0;accepted<=0;
            pixel_started<=0;pixel_bytes_remaining<=0;
            pixel_valid<=0;pixel<=0;complete<=0;error<=0;
        end else begin
            header_fields_ok<=signature==16'h4d42 && dib>=40 &&
                {32'd0,dib}+14<={32'd0,pixel_offset} && planes==1 && bpp==24 &&
                compression==0 && pixel_offset>=54;
            pixel_start_offset<=pixel_offset-1'b1;
            pixel_valid<=0;complete<=0;
            if(valid && error==0) begin
                expected_offset<=expected_offset+1'b1;
                if(offset!=expected_offset || offset>=file_size) error<=3;
                if(header_position<54) header_position<=header_position+1'b1;
                case(header_position)
                    0:signature[7:0]<=data==8'h42 ? 8'h42 : 8'd0; 1:signature[15:8]<=data==8'h4d ? 8'h4d : 8'd0;
                    2:declared_size[7:0]<=data;3:declared_size[15:8]<=data;
                    4:declared_size[23:16]<=data;5:declared_size[31:24]<=data;
                    10:pixel_offset[7:0]<=data;11:pixel_offset[15:8]<=data;
                    12:pixel_offset[23:16]<=data;13:pixel_offset[31:24]<=data;
                    14:dib[7:0]<=data;15:dib[15:8]<=data;16:dib[23:16]<=data;17:dib[31:24]<=data;
                    18:width[7:0]<=data;19:width[15:8]<=data;20:width[23:16]<={7'd0,|data};21:width[31:24]<={7'd0,|data};
                    22:height[7:0]<=data;23:height[15:8]<=data;24:height[23:16]<={7'd0,|data};25:height[31:24]<={7'd0,|data};
                    26:planes[7:0]<=data==8'd1 ? 8'd1 : 8'd0;27:planes[15:8]<={7'd0,|data};28:bpp[7:0]<=data==8'd24 ? 8'd24 : 8'd0;29:bpp[15:8]<={7'd0,|data};
                    30:compression[7:0]<={7'd0,|data};31:compression[15:8]<={7'd0,|data};
                    32:compression[23:16]<={7'd0,|data};33:compression[31:24]<={7'd0,|data};
                    53:begin
                        accepted<=header_ok;
                        if(!header_ok) error<=1;
                        else begin
                            pixel_bytes_remaining<=image_bytes[31:0];
                            if(pixel_offset==54) pixel_started<=1;
                        end
                    end
                endcase
                if(accepted && !pixel_started && offset==pixel_start_offset)
                    pixel_started<=1;
                if(accepted && pixel_started && pixel_bytes_remaining!=0) begin
                    pixel_bytes_remaining<=pixel_bytes_remaining-1'b1;
                    if(row_byte==stride-1) row_byte<=0;else row_byte<=row_byte+1'b1;
                    if(row_byte<row_bytes) begin
                        case(phase)
                            0:begin blue<=data;phase<=1;end
                            1:begin green<=data;phase<=2;end
                            2:begin pixel<={data,green,blue};pixel_valid<=1;phase<=0;pixels<=pixels+1'b1;end
                        endcase
                    end
                end
            end
            if(done) begin
                complete<=1;
                if(upstream_error!=0) error<=upstream_error==8'h10 ?2:3;
                else if(error==0 && (!accepted || expected_offset!=file_size ||
                        pixels!={16'd0,width_expected}*height_expected || phase!=0)) error<=3;
            end
        end
    end
endmodule
