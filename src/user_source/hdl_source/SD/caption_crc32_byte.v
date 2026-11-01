`timescale 1ns/1ps
// Eight serial reflected CRC-32/ISO-HDLC steps. Stored result is not inverted.
module caption_crc32_byte (
    input wire clk,rst,start,
    input wire [31:0] seed,
    input wire [7:0] data,
    output reg busy,done,
    output reg [31:0] result
);
    reg [31:0] work;
    reg [2:0] count;
    wire [31:0] next_crc=work[0] ? (work>>1)^32'hedb88320 : work>>1;
    always @(posedge clk or posedge rst) begin
        if(rst) begin work<=0;count<=0;busy<=0;done<=0;result<=0;end
        else begin
            done<=0;
            if(start && !busy) begin work<=seed^{24'd0,data};count<=0;busy<=1;end
            else if(busy) begin
                work<=next_crc;
                if(count==7) begin result<=next_crc;busy<=0;done<=1;end
                else count<=count+1'b1;
            end
        end
    end
endmodule
