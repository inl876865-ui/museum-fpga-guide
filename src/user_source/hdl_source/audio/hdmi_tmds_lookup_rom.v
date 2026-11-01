`timescale 1ns/1ps
// Two identical copies provide three simultaneous reads without extra latency.
// Each 1024x16 copy occupies two 9K BRAMs; copy01 shares its two read ports.
module hdmi_tmds_lookup_rom (
    input wire clk,
    input wire [9:0] address0,address1,address2,
    output reg [15:0] data0,data1,data2
);
    (* ram_style="bram" *) reg [15:0] copy01[0:1023];
    (* ram_style="bram" *) reg [15:0] copy2[0:1023];
    function [15:0] table_word;
        input [9:0] address;
        integer index,ones,balance,delta;
        reg use_xnor;
        reg [8:0] q_m;
        reg [9:0] video_symbol;
        begin
            table_word=0;ones=0;balance=0;delta=0;q_m=0;video_symbol=0;use_xnor=0;
            if(address[9:8]!=3) begin
                for(index=0;index<8;index=index+1) ones=ones+address[index];
                use_xnor=ones>4 || (ones==4 && address[0]==0);
                q_m[0]=address[0];
                for(index=1;index<8;index=index+1)
                    q_m[index]=use_xnor ? q_m[index-1] ~^ address[index] : q_m[index-1] ^ address[index];
                q_m[8]=!use_xnor;ones=0;
                for(index=0;index<8;index=index+1) ones=ones+q_m[index];
                balance=2*ones-8;
                if(address[9:8]==0 || balance==0) begin
                    video_symbol={!q_m[8],q_m[8],(q_m[8] ? q_m[7:0] : ~q_m[7:0])};
                    delta=q_m[8] ? balance : -balance;
                end else if((address[9:8]==1 && balance>0) || (address[9:8]==2 && balance<0)) begin
                    video_symbol={1'b1,q_m[8],~q_m[7:0]};
                    delta=-balance+(q_m[8] ? 2 : 0);
                end else begin
                    video_symbol={1'b0,q_m[8],q_m[7:0]};
                    delta=balance-(q_m[8] ? 0 : 2);
                end
                table_word[9:0]=video_symbol;table_word[15:10]=delta;
            end else begin
                case(address[5:4])
                    0:case(address[1:0])
                        0:table_word[9:0]=10'b1101010100;
                        1:table_word[9:0]=10'b0010101011;
                        2:table_word[9:0]=10'b0101010100;
                        3:table_word[9:0]=10'b1010101011;
                    endcase
                    1:table_word[9:0]=address[7:6]==1 ? 10'b0100110011 : 10'b1011001100;
                    2:case(address[3:0])
                        0:table_word[9:0]=10'b1010011100;1:table_word[9:0]=10'b1001100011;
                        2:table_word[9:0]=10'b1011100100;3:table_word[9:0]=10'b1011100010;
                        4:table_word[9:0]=10'b0101110001;5:table_word[9:0]=10'b0100011110;
                        6:table_word[9:0]=10'b0110001110;7:table_word[9:0]=10'b0100111100;
                        8:table_word[9:0]=10'b1011001100;9:table_word[9:0]=10'b0100111001;
                        10:table_word[9:0]=10'b0110011100;11:table_word[9:0]=10'b1011000110;
                        12:table_word[9:0]=10'b1010001110;13:table_word[9:0]=10'b1001110001;
                        14:table_word[9:0]=10'b0101100011;15:table_word[9:0]=10'b1011000011;
                    endcase
                    3:begin
                        if(address[7:6]!=0) table_word[9:0]=10'b0100110011;
                        else case(address[1:0])
                            0:table_word[9:0]=10'b1010001110;1:table_word[9:0]=10'b1001110001;
                            2:table_word[9:0]=10'b0101100011;3:table_word[9:0]=10'b1011000011;
                        endcase
                    end
                endcase
            end
        end
    endfunction
    integer address;
    initial for(address=0;address<1024;address=address+1) begin
        copy01[address]=table_word(address);copy2[address]=table_word(address);
    end
    always @(posedge clk) begin
        data0<=copy01[address0];data1<=copy01[address1];data2<=copy2[address2];
    end
endmodule
