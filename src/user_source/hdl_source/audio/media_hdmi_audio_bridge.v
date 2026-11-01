`timescale 1ns/1ps

// Player-owned boundary between the registered video bundle and the verified
// Route B HDMI packet/symbol chain. The EG4 DDR PHY remains in the board Top so
// this bridge can be exercised in ordinary RTL simulation without vendor pads.
// media_id drives the per-image tone selection and volume scales the output,
// turning the tone source into the audio half of the AV-linked feature.
module media_hdmi_audio_bridge #(
    parameter integer BLIP_SAMPLES = 4800,
    parameter integer ENABLE_WAV_TRANSPORT = 0,
    parameter integer ENABLE_TRANSITION_CUE = 0,
    parameter integer ENABLE_OUTPUT_MUTE = 0
) (
    input  wire        pixel_clk,
    input  wire        pixel_rst_n,
    input  wire        video_hsync,
    input  wire        video_vsync,
    input  wire        video_de,
    input  wire [9:0]  video_x,
    input  wire [23:0] video_rgb,
    input  wire [1:0]  media_id,
    input  wire [7:0]  volume,
    input wire signed [15:0] cue_sample,
    input wire cue_valid,
    output wire cue_ready,
    input  wire        wav_valid,
    output wire        wav_ready,
    input  wire signed [15:0] wav_left,
    input  wire signed [15:0] wav_right,
    input  wire        wav_active,
    input  wire        wav_end,
    input  wire        wav_paused,
    input  wire        force_arpeggio,
    input  wire        audio_switching,
    output wire [1:0]  audio_status,
    output wire        audio_switch_ready,
    output wire        audio_pause_ack,
    output wire [9:0]  channel0_symbol,
    output wire [9:0]  channel1_symbol,
    output wire [9:0]  channel2_symbol,
    output wire        sequence_error,
    output wire        tone_overflow,
    output wire        pcm_contract_error,
    output wire        blip_active,
    output wire        pcm_tap_valid,
    output wire signed [15:0] pcm_tap_left,
    input wire output_mute
);
    wire arp_valid;
    wire arp_ready;
    wire use_wav;
    wire select_silence;
    wire [7:0] switch_gain;
    wire signed [15:0] arp_left;
    wire signed [15:0] arp_right;
    wire source_valid;
    wire source_ready;
    wire signed [15:0] source_left;
    wire signed [15:0] source_right;
    wire sample_valid;
    wire sample_ready;
    wire signed [15:0] sample_left;
    wire signed [15:0] sample_right;

    reg video_hsync_q;
    reg video_vsync_q;
    reg video_de_q;
    reg [9:0] video_x_q;
    reg [23:0] video_rgb_q;
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            video_hsync_q <= 1'b1;
            video_vsync_q <= 1'b1;
            video_de_q <= 1'b0;
            video_x_q <= 10'd0;
            video_rgb_q <= 24'h000000;
        end else begin
            video_hsync_q <= video_hsync;
            video_vsync_q <= video_vsync;
            video_de_q <= video_de;
            video_x_q <= video_x;
            video_rgb_q <= video_de ? video_rgb : 24'h000000;
        end
    end

    pcm_media_tone #(.BLIP_SAMPLES(BLIP_SAMPLES)) u_tone (
        .clk(pixel_clk), .rst_n(pixel_rst_n),
        .media_id(media_id), .volume(volume),
        .sample_valid(arp_valid), .sample_ready(use_wav ? 1'b1 : arp_ready),
        .sample_left(arp_left), .sample_right(arp_right),
        .overflow(tone_overflow), .blip_active(blip_active)
    );

    audio_source_control #(.ENABLE_TRANSPORT(ENABLE_WAV_TRANSPORT)) u_audio_source_control (
        .clk(pixel_clk),.rst_n(pixel_rst_n),
        .request_wav(!force_arpeggio && (ENABLE_WAV_TRANSPORT!=0 || !audio_switching)),
        .wav_paused(ENABLE_WAV_TRANSPORT!=0 && (wav_paused || audio_switching)),
        .wav_active(wav_active),.wav_end(wav_end),
        .sample_taken(source_valid && source_ready),
        .select_wav(use_wav),.select_silence(select_silence),.switch_gain(switch_gain),
        .display_status(audio_status)
    );
    assign audio_switch_ready=!use_wav;
    assign audio_pause_ack=ENABLE_WAV_TRANSPORT!=0 && wav_paused &&
                           !force_arpeggio && !wav_end && select_silence;
    audio_source_mux u_audio_source_mux (
        .clk(pixel_clk), .rst_n(pixel_rst_n),
        .wav_valid(wav_valid), .wav_ready(wav_ready),
        .wav_left(wav_left), .wav_right(wav_right),
        .wav_active(use_wav), .force_arpeggio(1'b0),
        .arp_valid(arp_valid), .arp_ready(arp_ready),
        .arp_left(select_silence ? 16'sd0 : arp_left),
        .arp_right(select_silence ? 16'sd0 : arp_right),
        .out_valid(source_valid), .out_ready(source_ready),
        .out_left(source_left), .out_right(source_right)
    );

    // Apply the current volume to WAV too. Register the selected sample so
    // menu volume changes cannot alter an already-stalled PCM transaction.
    reg gain_valid;
    reg signed [15:0] gain_left, gain_right;
    wire gain_ready;
    wire signed [24:0] scaled_left=source_left*$signed({1'b0,volume});
    wire signed [24:0] scaled_right=source_right*$signed({1'b0,volume});
    wire signed [15:0] selected_left=use_wav ? (scaled_left >>> 8) : source_left;
    wire signed [15:0] selected_right=use_wav ? (scaled_right >>> 8) : source_right;
    wire signed [24:0] faded_left=selected_left*$signed({1'b0,switch_gain});
    wire signed [24:0] faded_right=selected_right*$signed({1'b0,switch_gain});
    wire signed [15:0] before_cue_left=switch_gain==255 ? selected_left : (faded_left >>> 8);
    wire signed [15:0] before_cue_right=switch_gain==255 ? selected_right : (faded_right >>> 8);
    wire signed [15:0] with_cue_left,with_cue_right;
    generate if(ENABLE_TRANSITION_CUE!=0) begin : g_cue_mix
    transition_cue_mixer u_cue_mixer (.clk(pixel_clk),.rst_n(pixel_rst_n),
        .source_valid(source_valid),.source_ready(),.source_left(before_cue_left),.source_right(before_cue_right),
        .cue_sample(cue_sample),.cue_valid(ENABLE_TRANSITION_CUE!=0 && cue_valid),
        .cue_ready(cue_ready),.volume(volume),.mixed_valid(),.mixed_ready(source_ready),
        .mixed_left(with_cue_left),.mixed_right(with_cue_right));
    end else begin : g_no_cue_mix
        assign with_cue_left=before_cue_left;assign with_cue_right=before_cue_right;assign cue_ready=0;
    end endgenerate
    assign source_ready=(!gain_valid || gain_ready) && (ENABLE_TRANSITION_CUE==0 || cue_valid);
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if(!pixel_rst_n) begin gain_valid<=0;gain_left<=0;gain_right<=0;end
        else if(!gain_valid || gain_ready) begin
            gain_valid<=source_valid && source_ready;
            if(source_valid && source_ready) begin
                gain_left<=ENABLE_OUTPUT_MUTE!=0 && output_mute ? 16'sd0 : ENABLE_TRANSITION_CUE!=0 ? with_cue_left : before_cue_left;
                gain_right<=ENABLE_OUTPUT_MUTE!=0 && output_mute ? 16'sd0 : ENABLE_TRANSITION_CUE!=0 ? with_cue_right : before_cue_right;
            end
        end
    end
    m06_pcm_contract_adapter u_m06_pcm_contract (
        .clk(pixel_clk), .rst_n(pixel_rst_n),
        .source_valid(gain_valid), .source_ready(gain_ready),
        .source_left(gain_left), .source_right(gain_right),
        .pcm_valid(sample_valid), .pcm_ready(sample_ready),
        .pcm_left(sample_left), .pcm_right(sample_right),
        .contract_error(pcm_contract_error)
    );

    hdmi_audio_symbol_core u_symbol_core (
        .pixel_clk(pixel_clk), .rst_n(pixel_rst_n),
        .video_hsync(video_hsync_q), .video_vsync(video_vsync_q),
        .video_de(video_de_q), .video_x(video_x_q), .video_rgb(video_rgb_q),
        .sample_valid(sample_valid), .sample_ready(sample_ready),
        .sample_left(sample_left), .sample_right(sample_right),
        .channel0_symbol(channel0_symbol),
        .channel1_symbol(channel1_symbol),
        .channel2_symbol(channel2_symbol),
        .sequence_error(sequence_error)
    );

    assign pcm_tap_valid = sample_valid && sample_ready;
    assign pcm_tap_left = sample_left;
endmodule
