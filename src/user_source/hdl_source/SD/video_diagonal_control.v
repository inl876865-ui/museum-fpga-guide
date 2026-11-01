`timescale 1ns/1ps
// Automatic commits animate; a manual commit cancels immediately to a hard cut.
module video_diagonal_control (
    input wire clk,rst,frame_start,active_valid,
    input wire [1:0] active_index,
    input wire auto_commit,selected,
    input wire [1:0] fade_level,
    output reg active,start_pulse,
    output reg [1:0] old_index,
    output reg [6:0] shift
);
    reg [1:0] index_q,auto_sync,level_q;
    reg valid_q,half_step;
    reg [5:0] elapsed,limit;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            index_q<=0;valid_q<=0;auto_sync<=0;level_q<=0;
            active<=0;start_pulse<=0;old_index<=0;shift<=0;elapsed<=0;limit<=0;half_step<=0;
        end else begin
            start_pulse<=0;
            index_q<=active_index;valid_q<=active_valid;
            auto_sync<={auto_sync[0],auto_commit};
            if(!active_valid) begin active<=0;shift<=0;end
            else if(valid_q && active_index!=index_q) begin
                active<=auto_sync[1] && selected && fade_level!=0;
                start_pulse<=auto_sync[1] && selected && fade_level!=0;
                old_index<=index_q;shift<=0;elapsed<=0;half_step<=0;
                level_q<=fade_level;
                limit<=fade_level==3 ? 32 : fade_level==2 ? 16 : 8;
            end else if(frame_start && active) begin
                if(elapsed==limit-1) begin active<=0;shift<=80;end
                else begin
                    elapsed<=elapsed+1'b1;half_step<=!half_step;
                    shift<=shift+(level_q==1 ? 7'd10 : level_q==2 ? 7'd5 : half_step ? 7'd3 : 7'd2);
                end
            end
        end
    end
endmodule
