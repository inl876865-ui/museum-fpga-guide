`timescale 1ns/1ps

// Sample the accepted bottom-up BMP stream into independent 160x120 SDRAM slots.
// Successful storage control, not the sampling engine, publishes ready bits.
module thumbnail_capture #(
    parameter integer FRAME_WIDTH=640,
    parameter integer FRAME_HEIGHT=480,
    parameter integer THUMB_WIDTH=FRAME_WIDTH/4,
    parameter integer THUMB_HEIGHT=FRAME_HEIGHT/4,
    parameter integer ENABLE_AREA_AVERAGE=0
) (
    input wire write_clk,write_rst,mem_clk,mem_rst,
    input wire write_req,
    input wire [4:0] image_index,
    input wire pixel_valid,load_active,
    input wire [31:0] pixel_data,
    input wire full_write_ack,full_write_finish,
    input wire publish_toggle,invalidate_toggle,
    input wire [4:0] publish_index,
    output wire combined_ack,
    output reg combined_finish,
    output reg [31:0] ready_mask,
    output wire overflow,
    output wire pixel_ready,
    input wire initialized,controller_busy,refresh_busy,grant,
    output wire pending,busy,app_write,
    output wire [20:0] app_address,
    output wire [31:0] app_data
);
    localparam [20:0] THUMB_BASE=FRAME_WIDTH*FRAME_HEIGHT*4;
    localparam [20:0] THUMB_WORDS=THUMB_WIDTH*THUMB_HEIGHT;
    reg [2:0] req_sync;
    reg [4:0] index_q,index_sync;
    reg needed,job_started,full_done,small_done;
    reg [1:0] publish_sync,invalidate_sync;
    reg publish_seen,invalidate_seen;
    reg [4:0] publish_id_q,publish_id_sync;
    wire thumb_ack,thumb_finish,fifo_clear,fifo_full;
    wire [8:0] fifo_used, fifo_wrusedw;
    wire thumb_req=req_sync[2] && needed;
    wire [20:0] base_address=THUMB_BASE+index_sync*THUMB_WORDS;
    reg [1:0] needed_sync;
    reg [9:0] stream_x;
    reg [8:0] stream_y;
    reg sample_overflow;
    wire sample_valid;
    wire [31:0] sample_data;
    generate if(ENABLE_AREA_AVERAGE!=0) begin : g_area_average
        localparam integer AREA_WIDTH=FRAME_WIDTH/8;
        localparam integer AREA_BITS=AREA_WIDTH<2 ? 1 : $clog2(AREA_WIDTH);
        // Each output pixel covers an 8x8 block. Duplicate it into the existing
        // 160x120 slot so the 80x60 display reader and all addresses stay intact.
        (* ram_style="bram" *) reg [41:0] block_sums[0:AREA_WIDTH-1];
        (* ram_style="bram" *) reg [23:0] output_row[0:AREA_WIDTH-1];
        reg [41:0] column_sum;
        reg [23:0] row_pixel;
        reg [10:0] horizontal_r,horizontal_g,horizontal_b;
        reg emitting,second_row,emit_valid;
        reg [AREA_BITS:0] emit_x;
        wire active=load_active && !write_req && needed_sync[1];
        // Reserve all320 words of a completed8-row block before consuming more input.
        assign pixel_ready=!needed_sync[1] || (!emitting && !emit_valid && fifo_wrusedw<=9'd128);
        wire [AREA_BITS-1:0] column=stream_x >> 3;
        wire [13:0] sum_r=(stream_y[2:0]==0 ? 14'd0 : column_sum[41:28])+
                          {3'd0,horizontal_r}+{6'd0,pixel_data[31:24]};
        wire [13:0] sum_g=(stream_y[2:0]==0 ? 14'd0 : column_sum[27:14])+
                          {3'd0,horizontal_g}+{6'd0,pixel_data[23:16]};
        wire [13:0] sum_b=(stream_y[2:0]==0 ? 14'd0 : column_sum[13:0])+
                          {3'd0,horizontal_b}+{6'd0,pixel_data[15:8]};
        wire [13:0] rounded_r=sum_r+14'd32;
        wire [13:0] rounded_g=sum_g+14'd32;
        wire [13:0] rounded_b=sum_b+14'd32;
        // RAM contents need no reset: the first row of every block starts at 0.
        always @(posedge write_clk) begin
            if(active && pixel_valid && stream_x[2:0]==0)
                column_sum<=block_sums[column];
            if(active && pixel_valid && stream_x[2:0]==7) begin
                block_sums[column]<={sum_r,sum_g,sum_b};
                if(stream_y[2:0]==7)
                    output_row[column]<={rounded_r[13:6],rounded_g[13:6],rounded_b[13:6]};
            end
            row_pixel<=output_row[emit_x[AREA_BITS:1]];
        end
        assign sample_valid=active && emit_valid;
        assign sample_data={row_pixel,8'd0};
        always @(posedge write_clk or posedge write_rst) begin
            if(write_rst) begin
                horizontal_r<=0;horizontal_g<=0;horizontal_b<=0;
                emitting<=0;second_row<=0;emit_valid<=0;emit_x<=0;
            end else if(!active) begin
                horizontal_r<=0;horizontal_g<=0;horizontal_b<=0;
                emitting<=0;second_row<=0;emit_valid<=0;emit_x<=0;
            end else begin
                emit_valid<=emitting;
                if(pixel_valid) begin
                    if(stream_x[2:0]==7) begin
                        horizontal_r<=0;horizontal_g<=0;horizontal_b<=0;
                        if(stream_x==FRAME_WIDTH-1 && stream_y[2:0]==7) begin
                            emitting<=1;second_row<=0;emit_x<=0;
                        end
                    end else begin
                        horizontal_r<=horizontal_r+pixel_data[31:24];
                        horizontal_g<=horizontal_g+pixel_data[23:16];
                        horizontal_b<=horizontal_b+pixel_data[15:8];
                    end
                end
                if(emitting) begin
                    if(emit_x==THUMB_WIDTH-1) begin
                        emit_x<=0;second_row<=1;
                        if(second_row) emitting<=0;
                    end else emit_x<=emit_x+1'b1;
                end
            end
        end
    end else begin : g_point_sample
        assign pixel_ready=!needed_sync[1] || (!fifo_full && fifo_wrusedw<9'd508);
        assign sample_valid=pixel_valid && !write_req && needed_sync[1] &&
                            stream_x[1:0]==0 && stream_y[1:0]==3;
        assign sample_data=pixel_data;
    end endgenerate
    assign overflow=sample_overflow && load_active;
    assign combined_ack=full_write_ack && (!needed || thumb_ack);
    always @(posedge write_clk or posedge write_rst) begin
        if(write_rst) begin
            needed_sync<=0;stream_x<=0;stream_y<=0;sample_overflow<=0;
        end else begin
            needed_sync<={needed_sync[0],needed};
            if(write_req || !load_active) begin stream_x<=0;stream_y<=0;sample_overflow<=0;end
            else if(pixel_valid) begin
                if(stream_x==FRAME_WIDTH-1) begin stream_x<=0;stream_y<=stream_y+1'b1;end
                else stream_x<=stream_x+1'b1;
            end
            if(!write_req && load_active && sample_valid && fifo_full) sample_overflow<=1;
        end
    end
    always @(posedge mem_clk or posedge mem_rst) begin
        if(mem_rst) begin
            req_sync<=0;index_q<=0;index_sync<=0;needed<=0;job_started<=0;
            full_done<=0;small_done<=0;combined_finish<=0;ready_mask<=0;
            publish_sync<=0;invalidate_sync<=0;publish_seen<=0;invalidate_seen<=0;
            publish_id_q<=0;publish_id_sync<=0;
        end else begin
            req_sync<={req_sync[1:0],write_req};index_q<=image_index;index_sync<=index_q;
            publish_sync<={publish_sync[0],publish_toggle};
            invalidate_sync<={invalidate_sync[0],invalidate_toggle};
            publish_id_q<=publish_index;publish_id_sync<=publish_id_q;
            combined_finish<=0;
            if(invalidate_sync[1]!=invalidate_seen) begin
                invalidate_seen<=invalidate_sync[1];ready_mask<=0;
            end else if(publish_sync[1]!=publish_seen) begin
                publish_seen<=publish_sync[1];ready_mask[publish_id_sync]<=1;
            end
            if(req_sync[1] && !req_sync[2]) begin
                needed<=!ready_mask[index_sync];full_done<=0;small_done<=0;job_started<=1;
            end
            if(full_write_finish) full_done<=1;
            if(thumb_finish) small_done<=1;
            if(job_started && !req_sync[2] && full_done && (small_done || !needed)) begin
                combined_finish<=1;job_started<=0;
            end
        end
    end
    wfifo_32_32_512 u_fifo (
        .clkw(write_clk),.clkr(mem_clk),.rst(fifo_clear),
        .we(sample_valid),.di(sample_data),.re(app_write),.dout(app_data),
        .full_flag(fifo_full),.empty_flag(),.wrusedw(fifo_wrusedw),.rdusedw(fifo_used)
    );
    frame_fifo_write #(.FRAME_WIDTH(THUMB_WIDTH),.FRAME_HEIGHT(THUMB_HEIGHT),
        .BURST_SIZE(128),.COUNT_BITS($clog2(THUMB_WIDTH*THUMB_HEIGHT+129)),
        .X_BITS($clog2(THUMB_WIDTH))) u_writer (
        .rst(mem_rst),.mem_clk(mem_clk),.Sdr_init_done(initialized),
        .Sdr_init_ref_vld(refresh_busy),.Sdr_busy(controller_busy),
        .App_rd_busy(!grant),.O_wr_busy(busy),.App_wr_en(app_write),.App_wr_addr(app_address),
        .write_req(thumb_req),.write_req_ack(thumb_ack),.write_finish(thumb_finish),
        .write_addr_0(base_address),.write_addr_1(base_address),
        .write_addr_2(base_address),.write_addr_3(base_address),.write_addr_index(2'd0),
        .write_len(THUMB_WORDS),.fifo_aclr(fifo_clear),.rdusedw({1'b0,fifo_used}),
        .pending(pending)
    );
endmodule
