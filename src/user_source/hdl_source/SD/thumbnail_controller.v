`timescale 1ns/1ps

// Reuse the menu's debounced key events. Logical picture IDs, not SDRAM banks.
module thumbnail_controller #(parameter integer RESIDENT_MODE=0,
    parameter integer RESPONSIVE_SELECTION=0,
    parameter integer CONFIRM_SELECTION=0) (
    input wire clk,rst,
    input wire enter,next_key,prev_key,confirm_key,back_key,
    input wire [5:0] image_count,
    input wire [4:0] current_image,
    input wire [31:0] thumbnail_ready,failed_images,
    input wire selection_done,selection_failed,
    output reg view_mode,waiting,
    output reg [4:0] focus_index,target_index,
    output reg select_event
);
    reg [4:0] current_image_q;
    reg confirm_pending;
    reg [4:0] confirmed_index;
    reg [31:0] target_onehot;
    wire target_bad=|(target_onehot & failed_images);
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            view_mode<=0;waiting<=0;focus_index<=0;target_index<=0;target_onehot<=32'd1;select_event<=0;current_image_q<=0;confirm_pending<=0;confirmed_index<=0;
        end else begin
            select_event<=0;current_image_q<=current_image;
            if(RESIDENT_MODE!=0 && CONFIRM_SELECTION!=0) begin
                if(!enter || image_count==0) begin
                    view_mode<=0;waiting<=0;confirm_pending<=0;
                end else if(!view_mode) begin
                    view_mode<=1;waiting<=0;confirm_pending<=0;
                    focus_index<=current_image<image_count ? current_image : 5'd0;
                end else begin
                    if(waiting && (selection_done || selection_failed || target_bad))
                        waiting<=0;
                    if(next_key && !prev_key)
                        focus_index<=focus_index>=image_count-1'b1 ? 5'd0 : focus_index+1'b1;
                    else if(prev_key && !next_key)
                        focus_index<=focus_index==0 ? image_count-1'b1 : focus_index-1'b1;
                    else if(current_image!=current_image_q && focus_index==current_image_q &&
                            !waiting && !confirm_pending)
                        focus_index<=current_image;
                    // Capture the confirmed ID, not a focus that may move later.
                    // Keep the in-flight target and newest confirmation while loading.
                    if(confirm_key && !next_key && !prev_key && focus_index<image_count &&
                            !failed_images[focus_index]) begin
                        confirmed_index<=focus_index;confirm_pending<=1;
                    end
                    if(!waiting && confirm_pending && !confirm_key) begin
                        confirm_pending<=0;
                        if(confirmed_index<image_count && confirmed_index!=current_image &&
                                !selection_failed && !failed_images[confirmed_index] &&
                                (RESPONSIVE_SELECTION!=0 || thumbnail_ready[confirmed_index])) begin
                            target_index<=confirmed_index;target_onehot<=32'd1<<confirmed_index;select_event<=1;waiting<=1;
                        end
                    end
                end
            end else if(RESIDENT_MODE!=0) begin
                if(!enter || image_count==0) begin view_mode<=0;waiting<=0;end
                else if(!view_mode) begin
                    view_mode<=1;waiting<=0;
                    focus_index<=current_image<image_count ? current_image : 5'd0;
                end else if(waiting) begin
                    if(selection_done || selection_failed || target_bad) waiting<=0;
                    // Preserve the requested bank until ACK, but keep the latest
                    // user focus so rapid keys are not dropped during SD loading.
                    if(RESPONSIVE_SELECTION!=0) begin
                        if(next_key && !prev_key)
                            focus_index<=focus_index>=image_count-1'b1 ? 5'd0 : focus_index+1'b1;
                        else if(prev_key && !next_key)
                            focus_index<=focus_index==0 ? image_count-1'b1 : focus_index-1'b1;
                    end
                end else if(next_key && !prev_key)
                    focus_index<=focus_index>=image_count-1'b1 ? 5'd0 : focus_index+1'b1;
                else if(prev_key && !next_key)
                    focus_index<=focus_index==0 ? image_count-1'b1 : focus_index-1'b1;
                else if(current_image!=current_image_q && focus_index==current_image_q)
                    focus_index<=current_image;
                else if(!selection_failed && focus_index!=current_image && focus_index<image_count &&
                        (RESPONSIVE_SELECTION!=0 || thumbnail_ready[focus_index]) && !failed_images[focus_index]) begin
                    target_index<=focus_index;target_onehot<=32'd1<<focus_index;select_event<=1;waiting<=1;
                end
            end else if(enter && image_count!=0) begin
                view_mode<=1;waiting<=0;
                focus_index<=current_image<image_count ? current_image : 5'd0;
            end else if(view_mode) begin
                if(waiting) begin
                    if(selection_done) begin view_mode<=0;waiting<=0;end
                    else if(selection_failed || target_bad) waiting<=0;
                end else if(back_key) view_mode<=0;
                else if(confirm_key && focus_index<image_count &&
                        thumbnail_ready[focus_index] && !failed_images[focus_index]) begin
                    target_index<=focus_index;target_onehot<=32'd1<<focus_index;select_event<=1;waiting<=1;
                end else if(next_key && !prev_key)
                    focus_index<=focus_index>=image_count-1'b1 ? 5'd0 : focus_index+1'b1;
                else if(prev_key && !next_key)
                    focus_index<=focus_index==0 ? image_count-1'b1 : focus_index-1'b1;
            end
        end
    end
endmodule
