`timescale 1ns/1ps
// Observe actual PCM starts; no audio sample, pointer or bus ownership is changed.
module audio_image_binding #(parameter integer IMAGE_BITS=5) (
    input wire clk,rst,pixel_clk,pixel_rst,
    input wire [3:0] file_tag,
    input wire stream_reset_pixel,sample_started,
    input wire enabled,manual_event,submitted,
    input wire [IMAGE_BITS-1:0] submitted_target,
    input wire [IMAGE_BITS:0] image_count,
    input wire [31:0] failed_images,
    input wire [IMAGE_BITS-1:0] current_image,
    output reg pending,
    output reg [IMAGE_BITS-1:0] target,
    output wire metadata_ready,
    output wire allowed_pixel,
    output wire [2:0] track_pixel
);
    wire [3:0] file_tag_pixel;
    player_settings_cdc #(.WIDTH(4),.RESET_VALUE(4'd0)) file_metadata (
        .src_clk(clk),.src_rst(rst),.src_value(file_tag),
        .dst_clk(pixel_clk),.dst_rst(pixel_rst),.dst_value(file_tag_pixel),.src_ready(metadata_ready));
    reg first_pending,started_toggle,playing_valid;
    reg [2:0] playing_track;
    always @(posedge pixel_clk or posedge pixel_rst) begin
        if(pixel_rst) begin
            first_pending<=0;started_toggle<=0;playing_valid<=0;playing_track<=0;
        end else if(stream_reset_pixel) begin
            first_pending<=0;playing_valid<=0;
        end else begin
            if(sample_started) first_pending<=1;
            // START_FILE waits for this acknowledged bundle; empty segments cannot confuse its identity.
            // The event follows the first real sample; no picture-readiness wait is introduced.
            if(first_pending) begin
                playing_track<=file_tag_pixel[2:0];playing_valid<=1;
                started_toggle<=!started_toggle;first_pending<=0;
            end
        end
    end
    wire [4:0] started_session;
    player_settings_cdc #(.WIDTH(5),.RESET_VALUE(5'd0)) started_metadata (
        .src_clk(pixel_clk),.src_rst(pixel_rst),.src_value({playing_valid,started_toggle,playing_track}),
        .dst_clk(clk),.dst_rst(rst),.dst_value(started_session));
    reg enabled_q,seen_toggle,manual_override;
    wire new_session=started_session[4] && started_session[3]!=seen_toggle;
    wire align_request=enabled && started_session[4] && (new_session || !enabled_q);
    always @(posedge clk or posedge rst) begin
        if(rst) begin pending<=0;target<=0;enabled_q<=0;seen_toggle<=0;manual_override<=0;end
        else begin
            enabled_q<=enabled;
            if(started_session[4]) seen_toggle<=started_session[3];
            if(!enabled) begin pending<=0;manual_override<=0;end
            else if(manual_event) begin pending<=0;manual_override<=1;end
            else if(align_request) begin
                manual_override<=0;
                target<=started_session[2:0];
                pending<=started_session[2:0]<image_count && !failed_images[started_session[2:0]] &&
                    started_session[2:0]!=current_image;
            end else if((submitted && submitted_target==target) || !started_session[4] || target>=image_count || failed_images[target]) pending<=0;
        end
    end
    (* async_reg="true" *) reg [1:0] allow_sync;
    always @(posedge pixel_clk or posedge pixel_rst) begin
        if(pixel_rst) allow_sync<=0;
        else allow_sync<={allow_sync[0],enabled && !manual_override && !manual_event && started_session[2:0]<image_count && !failed_images[started_session[2:0]]};
    end
    assign allowed_pixel=allow_sync[1] && playing_valid;
    assign track_pixel=playing_track;
endmodule
