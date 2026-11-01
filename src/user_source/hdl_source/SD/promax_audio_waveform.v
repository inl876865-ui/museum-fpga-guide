`timescale 1ns/1ps

// Time-domain amplitude bars, not FFT frequency bands. Keep the established
// module interface, pixel-clock PCM tap and frame-boundary ping-pong display.
module promax_audio_waveform #(
    parameter integer WAVE_X=64,
    parameter integer WAVE_Y=384,
    parameter integer WAVE_WIDTH=512,
    parameter integer WAVE_HEIGHT=96,
    parameter integer DECIMATE=8
) (
    input wire clk,rst_n,vsync,de,
    input wire [23:0] rgb_in,
    input wire [9:0] pixel_x,
    input wire enable,pcm_tap_valid,
    input wire signed [15:0] pcm_tap_left,
    output wire [23:0] rgb_out,
    output wire waveform_active
);
    localparam integer SAMPLE_COUNT=64;
    localparam integer SAMPLE_SPACING=WAVE_WIDTH/SAMPLE_COUNT;
    localparam integer CENTER_Y=WAVE_Y+WAVE_HEIGHT/2;
    localparam integer DECIMATE_BITS=DECIMATE<=1 ? 1 : $clog2(DECIMATE);
    reg [11:0] line_y;
    reg de_q,vs_q,enable_q;
    wire frame_start=vs_q && !vsync;
    reg [7:0] sample_bank0 [0:SAMPLE_COUNT-1];
    reg [7:0] sample_bank1 [0:SAMPLE_COUNT-1];
    reg write_bank,display_bank,display_valid;
    reg [6:0] capture_count;
    reg [DECIMATE_BITS-1:0] decimate_count;
    // Retain display-only x8 gain; the headphone PCM path is untouched.
    wire signed [18:0] visual_scaled={pcm_tap_left,3'b000};
    wire signed [15:0] visual_sample=visual_scaled>19'sd32767 ? 16'sh7fff :
        visual_scaled < -19'sd32768 ? 16'sh8000 : visual_scaled[15:0];
    wire [7:0] sample_abs=visual_sample[15] ?
                            (~visual_sample[15:8]+8'd1) : visual_sample[15:8];
    wire [7:0] previous_sample=display_valid ?
        (display_bank ? sample_bank1[capture_count[5:0]] : sample_bank0[capture_count[5:0]]) : 8'd0;
    wire [7:0] decayed_sample=previous_sample>8'd4 ? previous_sample-8'd4 : 8'd0;
    wire [7:0] capture_sample=sample_abs>decayed_sample ? sample_abs : decayed_sample;
    initial begin
        if(WAVE_X<0 || WAVE_Y<0 || WAVE_WIDTH<256 || WAVE_WIDTH%64!=0 ||
           WAVE_X+WAVE_WIDTH>640 || WAVE_HEIGHT<8 || WAVE_HEIGHT>128 ||
           WAVE_Y+WAVE_HEIGHT>480 || DECIMATE<1) begin
            $display("AUDIO_WAVEFORM_CONFIG_ERROR invalid bar viewport/decimation");
            $finish;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            line_y<=0;de_q<=0;vs_q<=1;enable_q<=0;
            write_bank<=0;display_bank<=1;display_valid<=0;
            capture_count<=0;decimate_count<=0;
        end else begin
            de_q<=de;vs_q<=vsync;
            if(!vsync) line_y<=0;
            else if(de_q && !de) line_y<=line_y+1'b1;
            if(frame_start) begin
                enable_q<=enable;
                if(enable && capture_count==SAMPLE_COUNT) begin
                    display_bank<=write_bank;display_valid<=1;
                    write_bank<=~write_bank;
                end else display_valid<=0;
                capture_count<=0;decimate_count<=0;
            end else if(enable && pcm_tap_valid && capture_count<SAMPLE_COUNT) begin
                if(decimate_count==0) begin
                    if(write_bank) sample_bank1[capture_count[5:0]]<=capture_sample;
                    else sample_bank0[capture_count[5:0]]<=capture_sample;
                    capture_count<=capture_count+1'b1;decimate_count<=DECIMATE-1;
                end else decimate_count<=decimate_count-1'b1;
            end
        end
    end

    function [23:0] column_color;
        input [5:0] index;
        begin case(index)
            6'd0: column_color=24'hf491c7;
            6'd1: column_color=24'hee92cb;
            6'd2: column_color=24'he993cf;
            6'd3: column_color=24'he494d4;
            6'd4: column_color=24'hdf95d8;
            6'd5: column_color=24'hda96dc;
            6'd6: column_color=24'hd597e1;
            6'd7: column_color=24'hd098e5;
            6'd8: column_color=24'hcb99ea;
            6'd9: column_color=24'hc69beb;
            6'd10: column_color=24'hc19eec;
            6'd11: column_color=24'hbca1ee;
            6'd12: column_color=24'hb7a4ef;
            6'd13: column_color=24'hb2a7f0;
            6'd14: column_color=24'hadaaf2;
            6'd15: column_color=24'ha8adf3;
            6'd16: column_color=24'ha4b0f5;
            6'd17: column_color=24'ha1b4f4;
            6'd18: column_color=24'h9fb9f3;
            6'd19: column_color=24'h9cbef2;
            6'd20: column_color=24'h9ac3f2;
            6'd21: column_color=24'h98c7f1;
            6'd22: column_color=24'h95ccf0;
            6'd23: column_color=24'h93d1ef;
            6'd24: column_color=24'h91d6ef;
            6'd25: column_color=24'h91d8e8;
            6'd26: column_color=24'h92dae2;
            6'd27: column_color=24'h92dcdc;
            6'd28: column_color=24'h93dfd6;
            6'd29: column_color=24'h93e1d0;
            6'd30: column_color=24'h94e3ca;
            6'd31: column_color=24'h94e5c4;
            6'd32: column_color=24'h95e8be;
            6'd33: column_color=24'h9be8b9;
            6'd34: column_color=24'ha2e9b5;
            6'd35: column_color=24'ha8e9b0;
            6'd36: column_color=24'hafeaac;
            6'd37: column_color=24'hb6eba8;
            6'd38: column_color=24'hbceba3;
            6'd39: column_color=24'hc3ec9f;
            6'd40: column_color=24'hcaed9b;
            6'd41: column_color=24'hcfeb9a;
            6'd42: column_color=24'hd5e99a;
            6'd43: column_color=24'hdae89a;
            6'd44: column_color=24'he0e69a;
            6'd45: column_color=24'he5e499;
            6'd46: column_color=24'hebe399;
            6'd47: column_color=24'hf0e199;
            6'd48: column_color=24'hf6e099;
            6'd49: column_color=24'hf5d89b;
            6'd50: column_color=24'hf5d19e;
            6'd51: column_color=24'hf5c9a0;
            6'd52: column_color=24'hf5c2a3;
            6'd53: column_color=24'hf4baa5;
            6'd54: column_color=24'hf4b3a8;
            6'd55: column_color=24'hf4abaa;
            6'd56: column_color=24'hf4a4ad;
            6'd57: column_color=24'hefa2b4;
            6'd58: column_color=24'heaa1bc;
            6'd59: column_color=24'he5a0c4;
            6'd60: column_color=24'he19fcc;
            6'd61: column_color=24'hdc9ed3;
            6'd62: column_color=24'hd79ddb;
            6'd63: column_color=24'hd29ce3;
            default: column_color=24'hce9beb;
        endcase end
    endfunction
    wire [9:0] local_x=pixel_x-WAVE_X;
    wire [5:0] sample_index=local_x/SAMPLE_SPACING;
    wire [9:0] cell_x=local_x%SAMPLE_SPACING;
    reg [7:0] selected_sample;
    wire [13:0] scaled_height=selected_sample*(WAVE_HEIGHT/2-2);
    wire [6:0] half_height=7'd1+(scaled_height>>7);
    // Viewport membership still uses every bit of line_y. Inside its legal
    // height <=128, the signed center difference is within -64..63, so
    // subtraction modulo256 followed by 8-bit absolute value is exact.
    localparam [7:0] CENTER_Y_LOW=CENTER_Y;
    wire signed [7:0] relative_y=line_y[7:0]-CENTER_Y_LOW;
    wire [7:0] distance_y=relative_y[7] ? -relative_y : relative_y;
    reg wave_pixel,panel_pixel;
    always @* begin
        selected_sample=0;wave_pixel=0;panel_pixel=0;
        if(enable_q && display_valid && de && pixel_x>=WAVE_X && pixel_x<WAVE_X+WAVE_WIDTH &&
           line_y>=WAVE_Y && line_y<WAVE_Y+WAVE_HEIGHT) begin
            panel_pixel=1;
            selected_sample=display_bank ? sample_bank1[sample_index] : sample_bank0[sample_index];
            // Three-pixel stems and one-pixel caps form mirrored fine bars.
            wave_pixel=cell_x>=SAMPLE_SPACING/2-1 && cell_x<=SAMPLE_SPACING/2+1 &&
                distance_y<=half_height && (distance_y<half_height || cell_x==SAMPLE_SPACING/2);
        end
    end
    assign waveform_active=wave_pixel;
    assign rgb_out=wave_pixel ? column_color(sample_index) : rgb_in;
endmodule
