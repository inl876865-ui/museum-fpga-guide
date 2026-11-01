`timescale 1ns/1ps
// Hold a complete in-flight DATA sector before consuming it at parser speed.
// FAT bytes never enter this buffer. A partial final DATA sector seals at file_done.
module caption_sector_buffer #(parameter integer EXTERNAL_RAM=0) (
    input wire clk,rst,start,
    input wire file_valid,
    input wire [7:0] file_byte,
    input wire file_done,
    input wire [7:0] file_error,
    output wire data_sector_allow,
    output reg byte_valid,
    output reg [7:0] byte_data,
    input wire byte_ready,
    output wire end_valid,
    output reg [7:0] end_error,
    output reg overflow,
    output wire [8:0] ram_address,
    output wire ram_write,
    output wire [7:0] ram_write_data,
    input wire [7:0] ram_read_data
);
    (* ram_style="bram" *) reg [7:0] bytes[0:511];
    reg [9:0] write_count,read_count;
    reg sealed,read_pending,finished;
    reg [7:0] ram_byte;
    assign ram_address=file_valid && !sealed && write_count<512 ? write_count[8:0] : read_count[8:0];
    assign ram_write=EXTERNAL_RAM!=0 && file_valid && !sealed && write_count<512;
    assign ram_write_data=file_byte;
    generate if(EXTERNAL_RAM!=0) begin : g_external_ram
        always @* ram_byte=ram_read_data;
    end else begin : g_internal_ram
        always @(posedge clk) begin
            if(file_valid && !sealed && write_count<512) bytes[write_count[8:0]]<=file_byte;
            ram_byte<=bytes[read_count[8:0]];
        end
    end endgenerate
    assign data_sector_allow=!sealed && write_count==0 && !finished && !byte_valid && !read_pending;
    assign end_valid=finished && !sealed && write_count==0 && !byte_valid && !read_pending;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            write_count<=0;read_count<=0;sealed<=0;read_pending<=0;finished<=0;
            byte_valid<=0;byte_data<=0;end_error<=0;overflow<=0;
        end else if(start) begin
            write_count<=0;read_count<=0;sealed<=0;read_pending<=0;finished<=0;
            byte_valid<=0;end_error<=0;overflow<=0;
        end else begin
            if(file_valid) begin
                if(sealed || write_count>=512 || finished) overflow<=1;
                else begin
                    write_count<=write_count+1'b1;
                    if(write_count==511) sealed<=1;
                end
            end
            if(file_done) begin
                finished<=1;end_error<=file_error;
                if(write_count!=0 || file_valid) sealed<=1;
            end
            if(sealed && !byte_valid && !read_pending && read_count<write_count) read_pending<=1;
            else if(read_pending) begin byte_data<=ram_byte;byte_valid<=1;read_pending<=0;end
            if(byte_valid && byte_ready) begin
                byte_valid<=0;
                if(read_count+1'b1>=write_count) begin sealed<=0;write_count<=0;read_count<=0;end
                else read_count<=read_count+1'b1;
            end
        end
    end
endmodule
