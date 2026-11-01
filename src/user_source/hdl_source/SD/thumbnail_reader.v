`timescale 1ns/1ps

// Two ping-pong rows, two tiles per row. Pixel requests carry stable metadata
// through a toggle handshake; a returned row is published only after draining.
module thumbnail_reader #(
    parameter integer FRAME_WIDTH=640,
    parameter integer FRAME_HEIGHT=480,
    parameter integer THUMB_WIDTH=160,
    parameter integer THUMB_HEIGHT=120,
    parameter integer DIRECTORY_LAYOUT=0,
    parameter integer ENABLE_PREVIEW=1
) (
    input wire mem_clk,mem_rst,pixel_clk,pixel_rst,
    input wire view_mode,frame_start,
    input wire [2:0] page_index,
    input wire [1:0] focus_slot,
    input wire [3:0] thumbnail_ready,
    input wire consume_row,
    input wire [8:0] consumed_row,display_row,
    input wire [9:0] pixel_address,
    output reg [31:0] pixel_data,
    output wire [1:0] display_mask,
    input wire initialized,controller_busy,refresh_busy,grant,
    input wire return_valid,
    input wire [31:0] return_data,
    output wire pending,busy,app_read,
    output wire [20:0] app_address
);
    localparam [20:0] THUMB_BASE=FRAME_WIDTH*FRAME_HEIGHT*4;
    localparam [20:0] THUMB_WORDS=THUMB_WIDTH*THUMB_HEIGHT;
    localparam [2:0] IDLE=0,LATCH=1,WAIT_GRANT=2,COMMAND=3,RETURN=4,DRAIN=5;
    localparam integer LINE_ADDR_BITS=DIRECTORY_LAYOUT!=0 && ENABLE_PREVIEW==0 ? 9 : 10;
    (* ram_style="bram" *) reg [31:0] line_memory[0:(1<<LINE_ADDR_BITS)-1];
    reg request_toggle,acknowledge;
    reg [15:0] request_packet;
    (* async_reg="true" *) reg [1:0] ack_sync,req_sync;
    reg request_cancelled;
    reg [8:0] next_row;
    reg request_waiting;
    reg [1:0] row_ready;
    reg [8:0] row_tag[0:1];
    reg [1:0] row_mask[0:1];
    localparam integer DISPLAY_ROWS=DIRECTORY_LAYOUT!=0 ? 352 : THUMB_HEIGHT*2;
    wire [1:0] left_entry=next_row<88 ? 2'd0 : next_row<176 ? 2'd1 : next_row<264 ? 2'd2 : 2'd3;
    wire [8:0] left_row=next_row-(left_entry==0 ? 0 : left_entry==1 ? 88 : left_entry==2 ? 176 : 264);
    wire [1:0] request_mask=DIRECTORY_LAYOUT!=0 ?
        {ENABLE_PREVIEW!=0 && next_row>=56 && next_row<296 && thumbnail_ready[focus_slot],
         left_row<60 && thumbnail_ready[left_entry]} :
        (next_row>=THUMB_HEIGHT ? thumbnail_ready[3:2] : thumbnail_ready[1:0]);
    assign display_mask=row_ready[display_row[0]] && row_tag[display_row[0]]==display_row ?
        row_mask[display_row[0]] : 2'b00;
    wire [LINE_ADDR_BITS-1:0] display_address=LINE_ADDR_BITS==9 ?
        {pixel_address[9],pixel_address[7:0]} : pixel_address;
    always @(posedge pixel_clk) pixel_data<=line_memory[display_address];
    always @(posedge pixel_clk or posedge pixel_rst) begin
        if(pixel_rst) begin
            request_toggle<=0;request_packet<=0;ack_sync<=0;request_cancelled<=0;next_row<=0;
            request_waiting<=0;row_ready<=0;row_tag[0]<=0;row_tag[1]<=0;row_mask[0]<=0;row_mask[1]<=0;
        end else begin
            ack_sync<={ack_sync[0],acknowledge};
            if(request_waiting && ack_sync[1]==request_toggle) begin
                request_waiting<=0;
                if(view_mode && !request_cancelled && !frame_start && request_packet[15:13]==page_index &&
                   (DIRECTORY_LAYOUT==0 || request_packet[12:11]==focus_slot)) begin
                    row_ready[request_packet[2]]<=1;
                    row_tag[request_packet[2]]<=request_packet[10:2];
                    row_mask[request_packet[2]]<=request_packet[1:0];
                end
            end
            if(consume_row) row_ready[consumed_row[0]]<=0;
            if(frame_start) begin
                if(request_waiting) request_cancelled<=1;
                next_row<=view_mode ? 9'd0 : DISPLAY_ROWS;
                row_ready<=0;
            end else if(view_mode && !request_waiting && next_row<DISPLAY_ROWS &&
                        !row_ready[next_row[0]]) begin
                request_packet<={page_index,focus_slot,next_row,request_mask};request_cancelled<=0;
                request_toggle<=~request_toggle;request_waiting<=1;next_row<=next_row+1'b1;
            end
        end
    end
    reg [2:0] state;
    reg request_seen,tile;
    reg [8:0] job_row;
    reg [1:0] job_focus;
    reg [2:0] job_page;
    reg [1:0] job_mask;
    reg [8:0] issued,returned;
    reg [20:0] base_address;
    reg [1:0] idle_history;
    wire drained=&idle_history;
    wire [1:0] job_entry=job_row<88 ? 2'd0 : job_row<176 ? 2'd1 : job_row<264 ? 2'd2 : 2'd3;
    wire [8:0] job_local=job_row-(job_entry==0 ? 0 : job_entry==1 ? 88 : job_entry==2 ? 176 : 264);
    wire [4:0] image_id=DIRECTORY_LAYOUT!=0 ? {job_page,(tile ? job_focus : job_entry)} :
        {job_page,job_row>=THUMB_HEIGHT,tile};
    wire [7:0] local_row=DIRECTORY_LAYOUT!=0 ? (tile ? (job_row-56)>>1 : job_local<<1) :
        (job_row>=THUMB_HEIGHT ? job_row-THUMB_HEIGHT : job_row);
    assign pending=state==WAIT_GRANT;
    assign busy=state==COMMAND || state==RETURN || state==DRAIN || (state==WAIT_GRANT && grant);
    assign app_read=state==COMMAND && issued<THUMB_WIDTH;
    assign app_address=base_address+issued;
    reg ram_write;
    reg [LINE_ADDR_BITS-1:0] ram_address;
    reg [31:0] ram_data;
    always @(negedge mem_clk or posedge mem_rst) begin
        if(mem_rst) begin ram_write<=0;ram_address<=0;ram_data<=0;end
        else begin
            ram_write<=(state==COMMAND || state==RETURN) && return_valid && returned<THUMB_WIDTH;
            ram_address<=LINE_ADDR_BITS==9 ? {job_row[0],returned[7:0]} :
                {job_row[0],tile,returned[7:0]};ram_data<=return_data;
        end
    end
    always @(posedge mem_clk) if(ram_write) line_memory[ram_address]<=ram_data;
    always @(posedge mem_clk or posedge mem_rst) begin
        if(mem_rst) begin
            req_sync<=0;request_seen<=0;acknowledge<=0;state<=IDLE;
            tile<=0;job_row<=0;job_page<=0;job_mask<=0;job_focus<=0;issued<=0;returned<=0;
            base_address<=0;idle_history<=0;
        end else begin
            req_sync<={req_sync[0],request_toggle};
            idle_history<={idle_history[0],!controller_busy && !refresh_busy};
            case(state)
                IDLE: if(req_sync[1]!=request_seen) begin request_seen<=req_sync[1];state<=LATCH;end
                LATCH: begin
                    job_page<=request_packet[15:13];job_row<=request_packet[10:2];job_focus<=request_packet[12:11];
                    job_mask<=request_packet[1:0];tile<=!request_packet[0];
                    if(request_packet[1:0]==0) begin acknowledge<=request_seen;state<=IDLE;end
                    else state<=WAIT_GRANT;
                end
                WAIT_GRANT: begin
                    issued<=0;returned<=0;
                    base_address<=THUMB_BASE+image_id*THUMB_WORDS+local_row*THUMB_WIDTH;
                    if(initialized && grant && drained) state<=COMMAND;
                end
                COMMAND: begin
                    if(app_read) issued<=issued+1'b1;
                    if(return_valid && returned<THUMB_WIDTH) returned<=returned+1'b1;
                    if(issued>=THUMB_WIDTH) state<=RETURN;
                end
                RETURN: begin
                    if(return_valid && returned<THUMB_WIDTH) returned<=returned+1'b1;
                    if(returned>=THUMB_WIDTH) state<=DRAIN;
                end
                DRAIN: if(drained) begin
                    if(!tile && job_mask[1]) begin tile<=1;state<=WAIT_GRANT;end
                    else begin acknowledge<=request_seen;state<=IDLE;end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
