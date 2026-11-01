`timescale 1ns/1ps

// Navigation and autoplay policy; storage owns loading and error recovery.
module media_player_control #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer ENABLE_REQUEST_GUARD = (CLK_FREQ_HZ==80_000_000),
    parameter integer AUTO_PLAY_MS = 3000,
    parameter integer MAX_IMAGES = 4,
    parameter integer IMAGE_BITS = $clog2(MAX_IMAGES),
    parameter integer ENABLE_THUMBNAILS = 0,
    parameter integer ENABLE_AUDIO_IMAGE_BIND = 0
) (
    input wire clk, rst,
    input wire next_event, prev_event, auto_event, auto_value,
    input wire restore_auto_valid, restore_auto_enabled,
    input wire period_change_valid,
    input wire [5:0] period_seconds,
    input wire period_cfg_valid,
    input wire [31:0] period_cfg_cycles,
    input wire scan_done,
    input wire [IMAGE_BITS:0] img_found_count,
    input wire [IMAGE_BITS-1:0] img_idx,
    input wire [MAX_IMAGES-1:0] failed_images, image_complete,
    input wire display_valid, load_busy,
    input wire recovery_blocked,
    input wire clear_requests, stop_playback, reset_timer, retry_next_event,
    input wire pix_clk, pix_rst, frame_start,
    input wire commit_image,
    input wire audio_image_bind,commit_is_bound,
    input wire [2:0] commit_track,
    input wire bound_allowed_pixel,
    input wire [2:0] bound_track_pixel,
    output wire commit_applied,
    input wire [1:0] commit_image_index,
    output reg frame_commit_request_toggle,
    output reg [1:0] frame_commit_request_index,
    output wire frame_commit_acknowledge_toggle,
    output wire [1:0] active_index,
    output wire active_valid,
    output reg auto_play_en,
    output reg [31:0] auto_cnt, auto_play_cycles,
    output reg next_req_pending, prev_req_pending,
    output reg [IMAGE_BITS:0] usable_next, usable_prev, usable_first,
    output wire [IMAGE_BITS:0] uncached_image,
    output wire selection_ready,
    output wire auto_tick,
    input wire browse_hold
);
    reg [IMAGE_BITS-1:0] selection_img_q;
    reg [IMAGE_BITS:0] selection_count_q;
    reg [MAX_IMAGES-1:0] selection_failed_q;
    reg selection_done;
    reg [IMAGE_BITS:0] uncached_choice_q,ahead_count_q;
    reg [IMAGE_BITS-1:0] ahead_index_q,ahead_source_q;
    reg [IMAGE_BITS:0] selection_step;
    reg [IMAGE_BITS-1:0] next_candidate,prev_candidate;
    reg auto_tick_q, auto_tick_seen;
    reg request_is_bound;reg [2:0] request_track;
    wire timer_hold=ENABLE_AUDIO_IMAGE_BIND!=0 && audio_image_bind;
    reg restore_auto_pending, restore_auto_value;
    wire frame_commit_pending =
        frame_commit_request_toggle != frame_commit_acknowledge_toggle;

    function [IMAGE_BITS-1:0] next_index_limited;
        input [IMAGE_BITS-1:0] cur;
        input [IMAGE_BITS:0] count;
        begin next_index_limited=count<2 || cur>=count-1'b1 ? 0 : cur+1'b1;end
    endfunction
    function [IMAGE_BITS-1:0] prev_index_limited;
        input [IMAGE_BITS-1:0] cur;
        input [IMAGE_BITS:0] count;
        begin prev_index_limited=count<2 ? 0 : cur==0 ? count-1'b1 : cur-1'b1;end
    endfunction

    function [IMAGE_BITS:0] select_image;
        input [IMAGE_BITS-1:0] current;
        input backwards;
        input [IMAGE_BITS:0] count;
        input [MAX_IMAGES-1:0] bad;
        reg [IMAGE_BITS-1:0] candidate;
        integer k;
        begin
            candidate = current;
            select_image = 0;
            for (k = 0; k < 4; k = k + 1) begin
                candidate = backwards ? prev_index_limited(candidate, count) :
                                        next_index_limited(candidate, count);
                if (!select_image[IMAGE_BITS] && {1'b0, candidate} < count && !bad[candidate])
                    select_image = {1'b1, candidate};
            end
        end
    endfunction

    function [IMAGE_BITS:0] select_uncached;
        input [IMAGE_BITS:0] count;
        input [MAX_IMAGES-1:0] bad, complete;
        integer k;
        begin
            select_uncached = 0;
            for (k = 0; k < 4; k = k + 1)
                if (!select_uncached[IMAGE_BITS] && k < count && !bad[k] && !complete[k])
                    select_uncached = {1'b1, k[IMAGE_BITS-1:0]};
        end
    endfunction

    assign uncached_image = MAX_IMAGES<=4 ? select_uncached(img_found_count, failed_images, image_complete) : uncached_choice_q;
    assign selection_ready = selection_img_q == img_idx &&
                             selection_count_q == img_found_count &&
                             selection_failed_q == failed_images && (MAX_IMAGES<=4 || selection_done);
    assign auto_tick = auto_tick_q && !auto_tick_seen && !period_change_valid;

    media_frame_commit #(.ENABLE_BOUND_CANCEL(ENABLE_AUDIO_IMAGE_BIND),
        .ENABLE_REQUEST_GUARD(ENABLE_REQUEST_GUARD)) u_media_frame_commit (
        .sd_clk(clk), .sd_rst(rst),
        .request_toggle(frame_commit_request_toggle),
        .request_index(frame_commit_request_index),
        .request_is_bound(request_is_bound),.request_track(request_track),
        .bound_allowed_pixel(bound_allowed_pixel),.bound_track_pixel(bound_track_pixel),.commit_applied(commit_applied),
        .acknowledge_toggle(frame_commit_acknowledge_toggle),
        .pixel_clk(pix_clk), .pixel_rst(pix_rst),
        .frame_start(frame_start),
        .active_index(active_index), .active_valid(active_valid)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            auto_play_en <= 0;
            restore_auto_pending <= 0;
            restore_auto_value <= 0;
            auto_cnt <= 0;
            auto_play_cycles <= (CLK_FREQ_HZ / 1000) * AUTO_PLAY_MS;
            next_req_pending <= 0;
            prev_req_pending <= 0;
            auto_tick_q <= 0;
            auto_tick_seen <= 0;
            frame_commit_request_toggle <= 0;
            frame_commit_request_index <= 0;request_is_bound<=0;request_track<=0;
            usable_next <= 0;
            usable_prev <= 0;
            usable_first <= 0;
            selection_img_q <= 0;
            selection_count_q <= 0;
            selection_failed_q <= 0;selection_done<=0;selection_step<=0;next_candidate<=0;prev_candidate<=0;
            uncached_choice_q<=0;ahead_count_q<=0;ahead_index_q<=0;ahead_source_q<=0;
        end else begin
            if (commit_image && !frame_commit_pending) begin
                frame_commit_request_index <= commit_image_index;
                request_is_bound<=ENABLE_AUDIO_IMAGE_BIND!=0 && commit_is_bound;request_track<=commit_track;
                frame_commit_request_toggle <= ~frame_commit_request_toggle;
            end
            if(MAX_IMAGES<=4) begin
                usable_next <= select_image(img_idx,1'b0,img_found_count,failed_images);
                usable_prev <= select_image(img_idx,1'b1,img_found_count,failed_images);
                usable_first <= select_image(img_found_count[IMAGE_BITS-1:0]-1'b1,1'b0,img_found_count,failed_images);
                selection_img_q<=img_idx;selection_count_q<=img_found_count;selection_failed_q<=failed_images;
            end else if(selection_img_q!=img_idx || selection_count_q!=img_found_count ||
                        selection_failed_q!=failed_images || !selection_done && selection_step==0) begin
                selection_img_q<=img_idx;selection_count_q<=img_found_count;selection_failed_q<=failed_images;
                selection_done<=0;selection_step<=1;
                usable_next<=0;usable_prev<=0;usable_first<=0;
                next_candidate<=next_index_limited(img_idx,img_found_count);
                prev_candidate<=prev_index_limited(img_idx,img_found_count);
            end else if(!selection_done) begin
                if(!usable_next[IMAGE_BITS]) begin
                    if(next_candidate<img_found_count && !failed_images[next_candidate])
                        usable_next<={1'b1,next_candidate};
                    next_candidate<=next_index_limited(next_candidate,img_found_count);
                end
                if(!usable_prev[IMAGE_BITS]) begin
                    if(prev_candidate<img_found_count && !failed_images[prev_candidate])
                        usable_prev<={1'b1,prev_candidate};
                    prev_candidate<=prev_index_limited(prev_candidate,img_found_count);
                end
                if(!usable_first[IMAGE_BITS] && selection_step-1'b1<img_found_count &&
                   !failed_images[selection_step-1'b1]) usable_first<={1'b1,selection_step[IMAGE_BITS-1:0]-1'b1};
                if(selection_step==MAX_IMAGES) selection_done<=1;
                else selection_step<=selection_step+1'b1;
            end
            // Use the fourth slot for the following forward image when neighbors are resident.
            ahead_index_q<=next_index_limited(usable_next[IMAGE_BITS-1:0],img_found_count);
            ahead_source_q<=usable_next[IMAGE_BITS-1:0];ahead_count_q<=img_found_count;
            uncached_choice_q<=0;
            if(MAX_IMAGES>4 && selection_ready) begin
                if(usable_next[IMAGE_BITS] && !image_complete[usable_next[IMAGE_BITS-1:0]])
                    uncached_choice_q<=usable_next;
                else if(usable_prev[IMAGE_BITS] && !image_complete[usable_prev[IMAGE_BITS-1:0]])
                    uncached_choice_q<=usable_prev;
                else if(usable_next[IMAGE_BITS] && ahead_source_q==usable_next[IMAGE_BITS-1:0] &&
                        ahead_count_q==img_found_count && ahead_index_q<img_found_count &&
                        !failed_images[ahead_index_q] && !image_complete[ahead_index_q])
                    uncached_choice_q<={1'b1,ahead_index_q};
            end
            auto_tick_q <= !timer_hold && !(ENABLE_THUMBNAILS!=0 && browse_hold) && !period_change_valid &&
                           !(period_cfg_valid && period_cfg_cycles != 0) &&
                           (auto_cnt >= auto_play_cycles - 1'b1);
            auto_tick_seen <= auto_tick_q;

            if (period_cfg_valid && period_cfg_cycles != 0)
                auto_play_cycles <= period_cfg_cycles;
            else if (period_change_valid)
                auto_play_cycles <= CLK_FREQ_HZ * period_seconds;

            if (restore_auto_valid) begin
                restore_auto_pending <= 1;
                restore_auto_value <= restore_auto_enabled;
            end else if (restore_auto_pending && scan_done) begin
                auto_play_en <= restore_auto_value && img_found_count > 1 && !recovery_blocked;
                restore_auto_pending <= 0;
            end
            if (auto_event) begin
                restore_auto_pending <= 0;
                if (!auto_value) auto_play_en <= 0;
                else if (scan_done && img_found_count > 1 && !recovery_blocked)
                    auto_play_en <= 1;
            end
            if (stop_playback) begin
                auto_play_en <= 0;
                restore_auto_pending <= 0;
            end

            if (next_event && scan_done && img_found_count != 0)
                next_req_pending <= 1;
            if (prev_event && scan_done && img_found_count != 0)
                prev_req_pending <= 1;
            if (auto_play_en && auto_tick && !auto_event)
                next_req_pending <= 1;
            if (retry_next_event)
                next_req_pending <= 1;
            if (clear_requests) begin
                next_req_pending <= 0;
                prev_req_pending <= 0;
            end

            if (!timer_hold && !(ENABLE_THUMBNAILS!=0 && browse_hold) && auto_play_en && display_valid && !load_busy && scan_done &&
                img_found_count > 1 && usable_next[IMAGE_BITS] && !recovery_blocked) begin
                if (auto_tick) auto_cnt <= 0;
                else auto_cnt <= auto_cnt + 1'b1;
            end else auto_cnt <= 0;
            if (auto_event || period_change_valid ||
                (period_cfg_valid && period_cfg_cycles != 0) || reset_timer)
                auto_cnt <= 0;
        end
    end
endmodule
