`timescale 1ns/1ps
// Shallow dual-clock BRAM with one held synchronous-read output slot.
// Both domains must share reset assertion and synchronize their own release.
module scaling_async_fifo #(
    parameter integer DATA_WIDTH=9,
    parameter integer ADDR_WIDTH=5
)(
    input wire wr_clk,wr_rst,
    input wire wr_valid,
    input wire [DATA_WIDTH-1:0] wr_data,
    output wire wr_ready,
    input wire rd_clk,rd_rst,
    output reg rd_valid,
    output wire [DATA_WIDTH-1:0] rd_data,
    input wire rd_ready
);
    (* ram_style="bram" *) reg [DATA_WIDTH-1:0] buffer[0:(1<<ADDR_WIDTH)-1];
    reg [ADDR_WIDTH:0] wr_ptr,rd_ptr,wr_gray,rd_gray;
    (* async_reg="true" *) reg [ADDR_WIDTH:0] wr_sync1,wr_sync2,rd_sync1,rd_sync2;
    reg read_pending;
    reg [DATA_WIDTH-1:0] ram_data;
    wire empty=rd_gray==wr_sync2;
    wire full=wr_gray=={~rd_sync2[ADDR_WIDTH:ADDR_WIDTH-1],rd_sync2[ADDR_WIDTH-2:0]};
    wire fetch=!rd_rst && !read_pending && (!rd_valid || rd_ready) && !empty;
    wire [ADDR_WIDTH:0] wr_next=wr_ptr+1'b1;
    wire [ADDR_WIDTH:0] rd_next=rd_ptr+1'b1;
    assign wr_ready=!wr_rst && !full;
    assign rd_data=ram_data;

    // RAM ports deliberately have no reset, including the read data register.
    always @(posedge wr_clk)
        if(wr_valid && wr_ready)buffer[wr_ptr[ADDR_WIDTH-1:0]]<=wr_data;
    always @(posedge rd_clk)
        if(fetch)ram_data<=buffer[rd_ptr[ADDR_WIDTH-1:0]];

    always @(posedge wr_clk or posedge wr_rst)begin
        if(wr_rst)begin wr_ptr<=0;wr_gray<=0;rd_sync1<=0;rd_sync2<=0;end
        else begin
            rd_sync1<=rd_gray;rd_sync2<=rd_sync1;
            if(wr_valid && wr_ready)begin wr_ptr<=wr_next;wr_gray<=wr_next^(wr_next>>1);end
        end
    end
    always @(posedge rd_clk or posedge rd_rst)begin
        if(rd_rst)begin rd_ptr<=0;rd_gray<=0;wr_sync1<=0;wr_sync2<=0;rd_valid<=0;read_pending<=0;end
        else begin
            wr_sync1<=wr_gray;wr_sync2<=wr_sync1;
            if(rd_valid && rd_ready)rd_valid<=0;
            if(read_pending)begin rd_valid<=1;read_pending<=0;end
            else if(fetch)begin
                rd_ptr<=rd_next;rd_gray<=rd_next^(rd_next>>1);
                rd_valid<=0;read_pending<=1;
            end
        end
    end
endmodule
