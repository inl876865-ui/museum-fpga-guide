`timescale 1ns/1ps

// Four-character audio status below the existing picture/error OSD.
// status: WAIT=0, WAV=1, TONE=2, DONE=3.
module audio_status_osd #(
    parameter integer OSD_X = 8,
    parameter integer OSD_Y = 20,
    parameter integer ENABLE_PAUSE_STATUS = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,
    input  wire [1:0]  status,
    input  wire        paused,
    input  wire        in_de,
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    output wire       osd_pixel
);
    reg [1:0] status_q;
    reg paused_q;
    reg [3:0] letter;
    reg [4:0] dots;
    reg hit;
    reg [2:0] row;
    reg [2:0] column;
    reg [1:0] place;

    localparam [3:0] L_W=0, L_A=1, L_V=2, L_T=3,
                     L_O=4, L_N=5, L_E=6, L_I=7, L_D=8, L_P=9, L_U=10, L_S=11;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin status_q<=0;paused_q<=0;end
        else if (frame_start) begin
            status_q<=status;paused_q<=ENABLE_PAUSE_STATUS!=0 && paused;
        end
    end

    function [4:0] font_row;
        input [3:0] value;
        input [2:0] y;
        begin
            case (value)
                L_W: case(y) 0,1,2,3,4,5:font_row=5'b10001;default:font_row=5'b01010;endcase
                L_A: case(y) 0:font_row=5'b01110;1,2:font_row=5'b10001;3:font_row=5'b11111;default:font_row=5'b10001;endcase
                L_V: case(y) 0,1,2,3,4:font_row=5'b10001;5:font_row=5'b01010;default:font_row=5'b00100;endcase
                L_T: case(y) 0:font_row=5'b11111;default:font_row=5'b00100;endcase
                L_O: case(y) 0,6:font_row=5'b01110;default:font_row=5'b10001;endcase
                L_N: case(y) 0,6:font_row=5'b10001;1,2:font_row=5'b11001;3:font_row=5'b10101;default:font_row=5'b10011;endcase
                L_E: case(y) 0,3,6:font_row=5'b11111;default:font_row=5'b10000;endcase
                L_I: case(y) 0,6:font_row=5'b11111;default:font_row=5'b00100;endcase
                L_D: case(y) 0,6:font_row=5'b11110;default:font_row=5'b10001;endcase
                L_P: case(y) 0,3:font_row=5'b11110;1,2:font_row=5'b10001;default:font_row=5'b10000;endcase
                L_U: case(y) 6:font_row=5'b01110;default:font_row=5'b10001;endcase
                L_S: case(y) 0,3,6:font_row=5'b01110;1,2:font_row=5'b10000;default:font_row=5'b00001;endcase
                default: font_row=5'b00000;
            endcase
        end
    endfunction

    always @* begin
        hit = 1'b0;
        letter = L_W;
        dots = 5'b00000;
        row = 3'd0;
        column = 3'd0;
        place = 2'd0;
        if (in_de && pixel_x >= OSD_X && pixel_x < OSD_X+32 &&
            pixel_y >= OSD_Y && pixel_y < OSD_Y+7) begin
            row = pixel_y - OSD_Y;
            column = (pixel_x - OSD_X) % 8;
            place = (pixel_x - OSD_X) / 8;
            if(paused_q) case(place)
                0:letter=L_P;1:letter=L_A;2:letter=L_U;3:letter=L_S;
            endcase else case (status_q)
                2'd0: case (place)
                    0:letter=L_W; 1:letter=L_A; 2:letter=L_I; 3:letter=L_T;
                endcase
                2'd1: case (place)
                    0:letter=L_W; 1:letter=L_A; 2:letter=L_V; 3:letter=L_E;
                endcase
                2'd2: case (place)
                    0:letter=L_T; 1:letter=L_O; 2:letter=L_N; 3:letter=L_E;
                endcase
                default: case (place)
                    0:letter=L_D; 1:letter=L_O; 2:letter=L_N; 3:letter=L_E;
                endcase
            endcase
            dots = font_row(letter, row);
            if (column < 5) hit = dots[4-column];
        end
    end
    assign osd_pixel = hit;
endmodule
