`timescale 1ns/1ps
// Display-only arithmetic. A shared serial divider stays outside the audio path.
module audio_progress_state (
    input wire clk,rst_n,frame_start,available,ended,
    input wire [3:0] file_tag,
    input wire [31:0] file_size,played_samples,
    output wire valid,
    output reg [23:0] elapsed_bcd,total_bcd,
    output reg long_time,
    output reg [4:0] fill_pixels
);
    reg valid_q,busy,published_end;
    reg [3:0] tag_q,published_tag;
    reg [31:0] samples_q,total_q,published_samples,published_total;
    reg end_q;
    reg [2:0] refresh_count,phase;
    reg [5:0] steps;
    reg [31:0] quotient;
    // Every job clamps samples to total=file_size>>1 (1..2^31-1).
    // Each ratio step keeps remainder<total, so 31 bits hold it exactly.
    reg [30:0] ratio_remainder;
    reg [15:0] remainder;
    // Seconds only need a constant48000 divisor and a16-bit remainder.
    wire [16:0] trial={remainder,quotient[31]};
    wire [17:0] difference={1'b0,trial}-18'd48000;
    wire subtract=!difference[17];
    wire [16:0] trial_result=subtract ? difference[16:0] : trial;
    wire [31:0] next_quotient={quotient[30:0],subtract};
    //30 small accumulation steps give floor(samples*30/total), without a wide divider.
    wire [31:0] ratio_sum={1'b0,ratio_remainder}+samples_q;
    wire [32:0] ratio_difference={1'b0,ratio_sum}-{1'b0,total_q};
    wire ratio_carry=!ratio_difference[32];
    reg [15:0] elapsed_seconds,total_seconds,seconds_left;
    reg [3:0] hours;
    reg [5:0] minutes;
    reg [23:0] elapsed_work,total_work;
    reg [4:0] fill_work;
    function [7:0] bcd60;
        input [5:0] n;
        begin
            case(n)
                6'd0:bcd60=8'h00;
                6'd1:bcd60=8'h01;
                6'd2:bcd60=8'h02;
                6'd3:bcd60=8'h03;
                6'd4:bcd60=8'h04;
                6'd5:bcd60=8'h05;
                6'd6:bcd60=8'h06;
                6'd7:bcd60=8'h07;
                6'd8:bcd60=8'h08;
                6'd9:bcd60=8'h09;
                6'd10:bcd60=8'h10;
                6'd11:bcd60=8'h11;
                6'd12:bcd60=8'h12;
                6'd13:bcd60=8'h13;
                6'd14:bcd60=8'h14;
                6'd15:bcd60=8'h15;
                6'd16:bcd60=8'h16;
                6'd17:bcd60=8'h17;
                6'd18:bcd60=8'h18;
                6'd19:bcd60=8'h19;
                6'd20:bcd60=8'h20;
                6'd21:bcd60=8'h21;
                6'd22:bcd60=8'h22;
                6'd23:bcd60=8'h23;
                6'd24:bcd60=8'h24;
                6'd25:bcd60=8'h25;
                6'd26:bcd60=8'h26;
                6'd27:bcd60=8'h27;
                6'd28:bcd60=8'h28;
                6'd29:bcd60=8'h29;
                6'd30:bcd60=8'h30;
                6'd31:bcd60=8'h31;
                6'd32:bcd60=8'h32;
                6'd33:bcd60=8'h33;
                6'd34:bcd60=8'h34;
                6'd35:bcd60=8'h35;
                6'd36:bcd60=8'h36;
                6'd37:bcd60=8'h37;
                6'd38:bcd60=8'h38;
                6'd39:bcd60=8'h39;
                6'd40:bcd60=8'h40;
                6'd41:bcd60=8'h41;
                6'd42:bcd60=8'h42;
                6'd43:bcd60=8'h43;
                6'd44:bcd60=8'h44;
                6'd45:bcd60=8'h45;
                6'd46:bcd60=8'h46;
                6'd47:bcd60=8'h47;
                6'd48:bcd60=8'h48;
                6'd49:bcd60=8'h49;
                6'd50:bcd60=8'h50;
                6'd51:bcd60=8'h51;
                6'd52:bcd60=8'h52;
                6'd53:bcd60=8'h53;
                6'd54:bcd60=8'h54;
                6'd55:bcd60=8'h55;
                6'd56:bcd60=8'h56;
                6'd57:bcd60=8'h57;
                6'd58:bcd60=8'h58;
                6'd59:bcd60=8'h59;
                6'd60:bcd60=8'h5a;
                6'd61:bcd60=8'h5b;
                6'd62:bcd60=8'h5c;
                6'd63:bcd60=8'h5d;
                default:bcd60=0;
            endcase
        end
    endfunction
    function [7:0] bcd_hours;
        input [3:0] n;
        begin bcd_hours=n>=10 ? {4'd1,n-4'd10} : {4'd0,n};end
    endfunction
    // Both time-conversion branches subtract from the same register in the
    // same clock; choosing the constant first shares their arithmetic.
    wire [15:0] seconds_decrement=seconds_left>=3600 ? 16'd3600 : 16'd60;
    wire [15:0] seconds_difference=seconds_left-seconds_decrement;
    assign valid=valid_q && available && published_tag==file_tag &&
        published_total==(file_size>>1) && played_samples>=published_samples;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_q<=0;busy<=0;published_end<=0;tag_q<=0;published_tag<=0;
            samples_q<=0;total_q<=0;published_samples<=0;published_total<=0;end_q<=0;
            refresh_count<=0;phase<=0;steps<=0;quotient<=0;remainder<=0;ratio_remainder<=0;
            elapsed_seconds<=0;total_seconds<=0;seconds_left<=0;hours<=0;minutes<=0;
            elapsed_work<=0;total_work<=0;fill_work<=0;
            elapsed_bcd<=0;total_bcd<=0;long_time<=0;fill_pixels<=0;
        end else begin
            if(frame_start) refresh_count<=refresh_count==5 ? 0 : refresh_count+1'b1;
            if(!available) valid_q<=0;
            if(!busy) begin
                if(available && file_size>=2 && (!valid ||
                    frame_start && refresh_count==0 || ended!=published_end)) begin
                    busy<=1;phase<=0;steps<=32;remainder<=0;
                    tag_q<=file_tag;total_q<=file_size>>1;end_q<=ended;
                    samples_q<=played_samples>(file_size>>1) ? file_size>>1 : played_samples;
                    quotient<=played_samples>(file_size>>1) ? file_size>>1 : played_samples;
                end
            end else if(phase<2) begin
                quotient<=next_quotient;remainder<=trial_result[15:0];steps<=steps-1'b1;
                if(steps==1) begin
                    remainder<=0;steps<=32;phase<=phase+1'b1;
                    case(phase)
                        0:begin
                            elapsed_seconds<=next_quotient[15:0];
                            quotient<=total_q+32'd47999;
                        end
                        1:begin
                            total_seconds<=next_quotient[15:0];
                            if(end_q && samples_q==total_q) elapsed_seconds<=next_quotient[15:0];
                            ratio_remainder<=0;fill_work<=0;steps<=30;
                        end
                    endcase
                end
            end else if(phase==2) begin
                ratio_remainder<=ratio_carry ? ratio_difference[30:0] : ratio_sum[30:0];
                if(ratio_carry) fill_work<=fill_work+1'b1;
                steps<=steps-1'b1;
                if(steps==1) begin
                    seconds_left<=elapsed_seconds;hours<=0;minutes<=0;phase<=3;
                end
            end else if(phase==3 || phase==4) begin
                if(seconds_left>=3600) begin seconds_left<=seconds_difference;hours<=hours+1'b1;end
                else if(seconds_left>=60) begin seconds_left<=seconds_difference;minutes<=minutes+1'b1;end
                else begin
                    if(phase==3) begin
                        elapsed_work<={bcd_hours(hours),bcd60(minutes),bcd60(seconds_left[5:0])};
                        seconds_left<=total_seconds;hours<=0;minutes<=0;phase<=4;
                    end else begin
                        total_work<={bcd_hours(hours),bcd60(minutes),bcd60(seconds_left[5:0])};phase<=5;
                    end
                end
            end else begin
                busy<=0;
                // A fast switch/reset invalidates an in-flight computation, never the audio.
                if(available && file_tag==tag_q && (file_size>>1)==total_q && played_samples>=samples_q) begin
                    elapsed_bcd<=elapsed_work;total_bcd<=total_work;
                    long_time<=total_seconds>=3600;fill_pixels<=fill_work;
                    published_tag<=tag_q;published_total<=total_q;published_samples<=samples_q;
                    published_end<=end_q;valid_q<=1;
                end
            end
        end
    end
endmodule
