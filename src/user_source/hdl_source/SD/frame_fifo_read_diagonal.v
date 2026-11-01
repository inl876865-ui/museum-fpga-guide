`timescale 1ns/1ps
// One output word per pixel: translated old triangles, stationary new middle.
// All segments share the original FIFO and four-client SDRAM arbiter.
module frame_fifo_read_diagonal #(
    parameter integer ADDR_BITS=21,BURST_SIZE=128,
    parameter integer FRAME_WIDTH=640,FRAME_HEIGHT=480
) (
    input wire rst,mem_clk,read_clk,initialized,refresh_busy,controller_busy,
    input wire return_valid,blocked,
    input wire read_req,
    output wire read_req_ack,
    input wire [1:0] read_index,old_index,new_index,
    input wire diagonal_active,
    input wire [6:0] diagonal_shift,
    input wire [8:0] fifo_used,
    output reg fifo_clear,
    output wire pending,busy,app_read,read_finish,fifo_write,
    output wire [ADDR_BITS-1:0] app_address
);
    localparam [3:0] IDLE=0,ACK=1,ROW=2,DIVIDE=3,ADDRESS=4,
        PREPARE=5,CHECK=6,BURST=7,ADVANCE=8,DONE=9,MOVE=10,BANK=11;
    localparam integer FRAME_WORDS=FRAME_WIDTH*FRAME_HEIGHT;
    localparam integer READ_BURST=BURST_SIZE>128 ? 128 : BURST_SIZE;
    localparam integer CENTER=3*(FRAME_WIDTH-1)-1;
    reg [1:0] req_pipe,ack_pipe;
    reg [13:0] descriptor_pixel;
    reg ack_mem;
    // Delay the request two pixel clocks so a same-frame commit settles first.
    always @(posedge read_clk or posedge rst) begin
        if(rst) begin req_pipe<=0;ack_pipe<=0;descriptor_pixel<=0;end
        else begin
            req_pipe<={req_pipe[0],read_req};ack_pipe<={ack_pipe[0],ack_mem};
            if(req_pipe[0] && !req_pipe[1])
                descriptor_pixel<={diagonal_active,old_index,new_index,diagonal_shift,read_index};
        end
    end
    assign read_req_ack=ack_pipe[1];
    (* async_reg="true" *) reg [2:0] req_sync;
    reg [13:0] descriptor_sync0,descriptor_sync1,job;
    reg [3:0] state;
    reg [ADDR_BITS-1:0] row_offset,address;
    reg [9:0] col,left_boundary,right_boundary,segment_end;
    reg signed [13:0] row_line;
    reg [10:0] left_num,right_num;
    reg [9:0] left_quot,right_quot;
    reg [1:0] left_rem,right_rem;
    reg [3:0] division_bit;
    reg [8:0] burst_target,sent,returned;
    reg [8:0] output_target;
    reg [1:0] skip_prefix;
    reg [3:0] delay_count;
    reg [1:0] idle_history;
    wire drained=&idle_history;
    wire [6:0] amount=job[8:2];
    wire [13:0] gap=({7'd0,amount}<<4)+({7'd0,amount}<<3)+amount;
    wire signed [13:0] left_limit=row_line-$signed(gap)+14'sd3;
    wire signed [13:0] right_limit=row_line+$signed(gap)+14'sd2;
    wire [2:0] left_trial={left_rem,left_num[10]};
    wire [2:0] right_trial={right_rem,right_num[10]};
    wire [9:0] next_left={left_quot[8:0],left_trial>=3};
    wire [9:0] next_right={right_quot[8:0],right_trial>=3};
    wire [1:0] source_bank=!job[13] ? job[1:0] :
        (col<left_boundary || col>=right_boundary ? job[12:11] : job[10:9]);
    wire [ADDR_BITS-1:0] translated_offset=amount*(FRAME_WIDTH*4+3);
    wire old_segment=job[13] && (col<left_boundary || col>=right_boundary);
    wire address_subtract=state==MOVE && col>=right_boundary;
    wire [ADDR_BITS-1:0] address_left=state==ADDRESS ? row_offset : address;
    wire [ADDR_BITS-1:0] address_right=state==ADDRESS ? col : state==MOVE ?
        translated_offset : state==BANK ? bank_base(source_bank) : 1;
    wire [ADDR_BITS-1:0] address_result=address_left+
        (address_subtract ? ~address_right : address_right)+address_subtract;
    function [ADDR_BITS-1:0] bank_base;
        input [1:0] bank;
        begin case(bank)
            0:bank_base=0;1:bank_base=FRAME_WORDS;
            2:bank_base=FRAME_WORDS*2;default:bank_base=FRAME_WORDS*3;
        endcase end
    endfunction
    function [10:0] clamp_limit;
        input signed [13:0] n;
        begin clamp_limit=n<0 ? 11'd0 : n>FRAME_WIDTH*3 ? FRAME_WIDTH*3 : n[10:0];end
    endfunction
    reg [9:0] target;
    always @* begin
        target=READ_BURST-{8'd0,address[1:0]};
        if(target>segment_end-col) target=segment_end-col;
        if(target>10'd256-{2'd0,address[7:0]}) target=10'd256-{2'd0,address[7:0]};
    end
    // Limit new diagonal reads to 128 words. This leaves 384 FIFO words of
    // headroom for the unchanged 128-word background write and read latency.
    // Reserve display priority while preparing each segment as well.
    assign pending=(state==ROW || state==DIVIDE || state==ADDRESS || state==MOVE || state==BANK || state==PREPARE ||
                    state==CHECK || state==ADVANCE) && fifo_used<512-READ_BURST && !req_sync[2];
    assign busy=state==BURST || (state==CHECK && pending && !blocked && drained);
    assign app_read=state==BURST && sent<burst_target;
    assign app_address=address;
    assign read_finish=state==DONE;
    assign fifo_write=state==BURST && return_valid && returned>=skip_prefix && returned<skip_prefix+output_target;
    always @(posedge mem_clk or posedge rst) begin
        if(rst) begin
            req_sync<=0;descriptor_sync0<=0;descriptor_sync1<=0;job<=0;
            state<=IDLE;ack_mem<=0;fifo_clear<=0;row_offset<=0;row_line<=CENTER;
            address<=0;col<=0;left_boundary<=0;right_boundary<=0;segment_end<=0;
            left_num<=0;right_num<=0;left_quot<=0;right_quot<=0;
            left_rem<=0;right_rem<=0;division_bit<=0;
            burst_target<=0;output_target<=0;skip_prefix<=0;
            sent<=0;returned<=0;delay_count<=0;idle_history<=0;
        end else begin
            req_sync<={req_sync[1:0],req_pipe[1]};
            descriptor_sync0<=descriptor_pixel;descriptor_sync1<=descriptor_sync0;
            idle_history<={idle_history[0],!controller_busy && !refresh_busy};
            case(state)
                IDLE: if(req_sync[2] && initialized) state<=ACK;
                ACK: begin
                    ack_mem<=1;fifo_clear<=1;job<=descriptor_sync1;
                    row_offset<=0;row_line<=CENTER;col<=0;
                    if(!req_sync[2]) begin ack_mem<=0;fifo_clear<=0;state<=ROW;end
                end
                ROW: begin
                    left_num<=clamp_limit(left_limit);right_num<=clamp_limit(right_limit);
                    left_quot<=0;right_quot<=0;left_rem<=0;right_rem<=0;division_bit<=10;
                    if(job[13]) state<=DIVIDE;
                    else begin left_boundary<=0;right_boundary<=FRAME_WIDTH;state<=ADDRESS;end
                end
                DIVIDE: begin
                    left_num<=left_num<<1;right_num<=right_num<<1;
                    left_rem<=left_trial>=3 ? left_trial-3 : left_trial;
                    right_rem<=right_trial>=3 ? right_trial-3 : right_trial;
                    left_quot<=next_left;right_quot<=next_right;
                    if(division_bit==0) begin left_boundary<=next_left;right_boundary<=next_right;state<=ADDRESS;end
                    else division_bit<=division_bit-1'b1;
                end
                ADDRESS: begin
                    address<=address_result;
                    segment_end<=!job[13] ? FRAME_WIDTH : col<left_boundary ? left_boundary :
                        col<right_boundary ? right_boundary : FRAME_WIDTH;
                    state<=old_segment ? MOVE : BANK;
                end
                MOVE: begin address<=address_result;state<=BANK;end
                BANK: begin address<=address_result;state<=PREPARE;end
                PREPARE: begin
                    // The shipped controller returns BL4. Align and discard the
                    // prefix/suffix instead of rounding the visible cut boundary.
                    output_target<=target;
                    skip_prefix<=address[1:0];
                    burst_target<=((target+address[1:0]+3)>>2)<<2;
                    address<={address[ADDR_BITS-1:2],2'b00};state<=CHECK;
                end
                CHECK: begin
                    if(req_sync[2]) state<=ACK;
                    else if(pending && !blocked && drained) begin
                        sent<=0;returned<=0;delay_count<=0;state<=BURST;
                    end
                end
                BURST: begin
                    if(app_read) begin address<=address_result;sent<=sent+1'b1;delay_count<=0;end
                    else if(delay_count<10) delay_count<=delay_count+1'b1;
                    if(return_valid && returned<burst_target) returned<=returned+1'b1;
                    if(sent>=burst_target && returned>=burst_target && delay_count==10 && drained)
                        state<=ADVANCE;
                end
                ADVANCE: begin
                    if(req_sync[2]) state<=ACK;
                    else if(col+output_target>=FRAME_WIDTH) begin
                        col<=0;row_offset<=row_offset+FRAME_WIDTH;row_line<=row_line-4;
                        state<=row_offset+FRAME_WIDTH>=FRAME_WORDS ? DONE : ROW;
                    end else begin col<=col+output_target;state<=ADDRESS;end
                end
                DONE: state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
