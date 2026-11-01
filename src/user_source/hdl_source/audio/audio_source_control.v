`timescale 1ns/1ps

// Switch audio sources at a PCM sample boundary with a short gain ramp.
// The WAV reader may keep filling its buffer while the tone is selected.
module audio_source_control #(parameter integer ENABLE_TRANSPORT=0) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       request_wav,
    input  wire       wav_active,
    input  wire       wav_end,
    input  wire       wav_paused,
    input  wire       sample_taken,
    output reg        select_wav,
    output reg        select_silence,
    output reg  [7:0] switch_gain,
    output wire [1:0] display_status
);
    localparam [1:0] STEADY=0, FADE_OUT=1, FADE_IN=2;
    reg [1:0] phase;
    wire pause_request = ENABLE_TRANSPORT!=0 && wav_paused;
    wire target_wav = request_wav && wav_active && !wav_end && !pause_request;
    wire target_silence = ENABLE_TRANSPORT!=0 && request_wav &&
                          (pause_request || !wav_active || wav_end);
    wire changing = target_wav!=select_wav || target_silence!=select_silence;

    // WAIT, WAV, TONE and DONE respectively.
    assign display_status = ENABLE_TRANSPORT!=0 ?
        (request_wav ? (wav_end ? 2'd3 :
         (wav_active && select_wav ? 2'd1 : 2'd0)) : 2'd2) : request_wav ?
        (wav_end ? 2'd3 : (!wav_active ? 2'd0 :
                          (select_wav ? 2'd1 : 2'd2))) :
        (select_wav ? 2'd1 : 2'd2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            select_wav <= 1'b0;
            select_silence <= ENABLE_TRANSPORT!=0;
            switch_gain <= ENABLE_TRANSPORT!=0 ? 8'd0 : 8'd255;
            phase <= STEADY;
        end else if (select_wav && !wav_active) begin
            // The WAV FIFO is drained. Release it without waiting for a
            // sample that cannot arrive. Song mode returns to silence.
            select_wav <= 1'b0;
            select_silence <= target_silence;
            switch_gain <= 8'd0;
            phase <= FADE_IN;
        end else case (phase)
            STEADY: if (changing)
                phase <= FADE_OUT;
            FADE_OUT: begin
                if (!changing)
                    phase <= FADE_IN;
                else if (sample_taken || select_silence) begin
                    if (switch_gain == 8'd0) begin
                        switch_gain <= 8'd0;
                        select_wav <= target_wav;
                        select_silence <= target_silence;
                        phase <= FADE_IN;
                    end else switch_gain <= switch_gain - 1'b1;
                end
            end
            FADE_IN: if (select_silence) begin
                switch_gain<=0;phase<=STEADY;
            end else if (sample_taken) begin
                if (switch_gain == 8'd255) begin
                    switch_gain <= 8'd255;
                    phase <= STEADY;
                end else switch_gain <= switch_gain + 1'b1;
            end
            default: phase <= STEADY;
        endcase
    end
endmodule
