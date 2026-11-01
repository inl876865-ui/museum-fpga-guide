`timescale 1ns/1ps
// Local warm-gold edge light; no frame memory, blur kernel or multiplier.
module video_diagonal_glow (
    input wire clk,rst_n,vsync,de,active,
    input wire [9:0] pixel_x,
    input wire [6:0] shift,
    input wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);
    reg de_q;
    reg [8:0] line_y;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin de_q<=0;line_y<=0;end
        else begin
            de_q<=de;
            if(!vsync) line_y<=0;
            else if(de_q && !de) line_y<=line_y+1'b1;
        end
    end
    wire signed [13:0] diagonal=$signed({1'b0,pixel_x,2'b00})-$signed({4'd0,pixel_x})+
                               $signed({3'd0,line_y,2'b00})-14'sd1916;
    wire [13:0] magnitude=diagonal<0 ? -diagonal : diagonal;
    wire [13:0] gap=({7'd0,shift}<<4)+({7'd0,shift}<<3)+shift;
    wire [13:0] distance=magnitude>gap ? magnitude-gap : gap-magnitude;
    reg [7:0] red_light,green_light,blue_light;
    always @* begin
        red_light=0;green_light=0;blue_light=0;
        if(distance<5) begin red_light=220;green_light=196;blue_light=140;end
        else if(distance<15) begin red_light=128;green_light=88;blue_light=32;end
        else if(distance<30) begin red_light=64;green_light=40;blue_light=12;end
        else if(distance<50) begin red_light=32;green_light=18;blue_light=4;end
        else if(distance<75) begin red_light=12;green_light=6;blue_light=0;end
        if(shift>=70) begin red_light=red_light>>2;green_light=green_light>>2;blue_light=blue_light>>2;end
        else if(shift>=60) begin red_light=red_light>>1;green_light=green_light>>1;blue_light=blue_light>>1;end
    end
    function [7:0] brighten;
        input [7:0] value,light;
        reg [8:0] sum;
        begin sum={1'b0,value}+{1'b0,light};brighten=sum[8] ? 8'hff : sum[7:0];end
    endfunction
    assign rgb_out=active && shift!=0 && de ? {
        brighten(rgb_in[23:16],red_light),brighten(rgb_in[15:8],green_light),
        brighten(rgb_in[7:0],blue_light)} : rgb_in;
endmodule
