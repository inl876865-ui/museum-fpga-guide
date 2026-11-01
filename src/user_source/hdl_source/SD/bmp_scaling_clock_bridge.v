`timescale 1ns/1ps
// Existing50MHz sector bytes -> actual25MHz scaler -> existing50MHz consumer.
module bmp_scaling_clock_bridge #(
    parameter integer FRAME_WIDTH=640,
    parameter integer FRAME_HEIGHT=480
)(
    input wire clk,rst,start,
    input wire scale_clk,scale_rst,
    input wire [31:0] file_size,
    input wire byte_valid,
    input wire [7:0] byte_data,
    output wire byte_ready,
    input wire end_valid,
    input wire [7:0] end_error,
    output wire pixel_valid,
    output wire [23:0] pixel,
    input wire pixel_ready,
    output reg complete,
    output reg [2:0] error
);
    localparam TX_WAIT=0,TX_START=1,TX_DATA=2,TX_ERROR=3,TX_STOP=4;
    localparam RX_WAIT=0,RX_START=1,RX_DATA=2,RX_ERROR=3,RX_DRAIN=4;
    localparam integer FRAME_PIXELS=FRAME_WIDTH*FRAME_HEIGHT;
    localparam integer COUNT_BITS=$clog2(FRAME_PIXELS+1);
    wire reset_request=rst || scale_rst || start;
    (* async_reg="true" *) reg [1:0] reset_source,reset_scale;
    wire control_reset_request=rst || scale_rst;
    (* async_reg="true" *) reg [1:0] control_reset_source;
    wire control_reset=control_reset_source[1];
    always @(posedge clk or posedge control_reset_request)begin
        if(control_reset_request)control_reset_source<=2'b11;
        else control_reset_source<={control_reset_source[0],1'b0};
    end
    wire source_reset=reset_source[1];
    wire core_reset=reset_scale[1];
    always @(posedge clk or posedge reset_request)begin
        if(reset_request)reset_source<=2'b11;
        else reset_source<={reset_source[0],1'b0};
    end
    always @(posedge scale_clk or posedge reset_request)begin
        if(reset_request)reset_scale<=2'b11;
        else reset_scale<={reset_scale[0],1'b0};
    end

    reg [2:0] tx_state,rx_state;
    reg active;
    // START prolongs source_reset. Replay an early START once control reset
    // releases, while both FIFOs still hold the same load reset as before.
    wire control_start=start || (!active && source_reset);
    wire input_wr_ready,input_rd_valid,input_rd_ready;
    wire [8:0] input_rd_data;
    wire input_wr_valid=active && !source_reset && !start &&
        (tx_state==TX_START || tx_state==TX_ERROR ||
         (tx_state==TX_DATA && (byte_valid || end_valid)));
    wire [8:0] input_wr_data=tx_state==TX_START ? {1'b1,8'd1} :
        tx_state==TX_ERROR ? {1'b1,end_error} : byte_valid ? {1'b0,byte_data} : {1'b1,8'd2};
    assign byte_ready=active && !source_reset && !start && tx_state==TX_DATA && input_wr_ready;
    scaling_async_fifo #(.DATA_WIDTH(9)) u_byte_fifo(
        .wr_clk(clk),.wr_rst(source_reset),.wr_valid(input_wr_valid),.wr_data(input_wr_data),.wr_ready(input_wr_ready),
        .rd_clk(scale_clk),.rd_rst(core_reset),.rd_valid(input_rd_valid),.rd_data(input_rd_data),.rd_ready(input_rd_ready));

    reg [31:0] file_size_scale;
    reg end_scale;
    reg [7:0] end_error_scale;
    reg protocol_error;
    wire core_start=rx_state==RX_START;
    wire core_byte_ready,core_pixel_valid,core_pixel_ready,core_complete;
    wire [23:0] core_pixel;
    wire [2:0] core_error;
    wire core_byte_valid=rx_state==RX_DATA && input_rd_valid && !input_rd_data[8];
    assign input_rd_ready=!core_reset && (rx_state==RX_WAIT || rx_state==RX_ERROR ||
        (rx_state==RX_DATA && (input_rd_data[8] || core_byte_ready)));
    bmp_adaptive_scaler #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT)) u_scaler(
        .clk(scale_clk),.rst(core_reset),.start(core_start),.file_size(file_size_scale),
        .byte_valid(core_byte_valid),.byte_data(input_rd_data[7:0]),.byte_ready(core_byte_ready),
        .end_valid(end_scale),.end_error(end_error_scale),
        .pixel_valid(core_pixel_valid),.pixel(core_pixel),.pixel_ready(core_pixel_ready),
        .complete(core_complete),.error(core_error),.source_width(),.source_height());
    always @(posedge scale_clk or posedge core_reset)begin
        if(core_reset)begin
            rx_state<=RX_WAIT;file_size_scale<=0;end_scale<=0;end_error_scale<=0;protocol_error<=0;
        end else case(rx_state)
            RX_WAIT:if(input_rd_valid)begin
                if(input_rd_data=={1'b1,8'd1})begin file_size_scale<=file_size;rx_state<=RX_START;end
                else protocol_error<=1;
            end
            RX_START:rx_state<=RX_DATA;
            RX_DATA:if(input_rd_valid && input_rd_ready && input_rd_data[8])begin
                if(input_rd_data[7:0]==2)rx_state<=RX_ERROR;
                else protocol_error<=1;
            end
            RX_ERROR:if(input_rd_valid)begin
                if(!input_rd_data[8])protocol_error<=1;
                end_error_scale<=input_rd_data[7:0];end_scale<=1;rx_state<=RX_DRAIN;
            end
            RX_DRAIN:rx_state<=RX_DRAIN;
            default:begin protocol_error<=1;rx_state<=RX_DRAIN;end
        endcase
    end

    wire output_wr_ready,output_rd_valid;
    wire output_rd_ready=pixel_ready && pixel_valid;
    assign core_pixel_ready=output_wr_ready && !core_reset && rx_state!=RX_WAIT && rx_state!=RX_START;
    scaling_async_fifo #(.DATA_WIDTH(24)) u_rgb_fifo(
        .wr_clk(scale_clk),.wr_rst(core_reset),.wr_valid(core_pixel_valid && core_pixel_ready),
        .wr_data(core_pixel),.wr_ready(output_wr_ready),
        .rd_clk(clk),.rd_rst(source_reset),.rd_valid(output_rd_valid),.rd_data(pixel),.rd_ready(output_rd_ready));

    // One status per load; payload is stable before request synchronization and
    // remains held until the common load reset. Error bypasses a full RGB FIFO.
    reg status_request;
    reg [2:0] status_error;
    (* async_reg="true" *) reg [1:0] status_sync;
    reg status_capture_pending,status_captured,success_seen;
    reg [COUNT_BITS-1:0] accepted_pixels;
    assign pixel_valid=output_rd_valid && active && !source_reset && !start && error==0 && accepted_pixels<FRAME_PIXELS;
    always @(posedge scale_clk or posedge core_reset)begin
        if(core_reset)begin status_request<=0;status_error<=0;end
        else if(!status_request && (protocol_error || core_error!=0 || core_complete))begin
            status_error<=protocol_error ? 3'd3 : core_error;status_request<=1;
        end
    end
    always @(posedge clk or posedge source_reset)begin
        if(source_reset)begin status_sync<=0;status_capture_pending<=0;status_captured<=0;end
        else begin
            status_sync<={status_sync[0],status_request};
            if(!status_captured && status_sync[1])begin
                if(!status_capture_pending)status_capture_pending<=1;
                else begin status_captured<=1;status_capture_pending<=0;end
            end
        end
    end
    always @(posedge clk or posedge control_reset)begin
        if(control_reset)begin
            tx_state<=TX_WAIT;active<=0;complete<=0;error<=0;accepted_pixels<=0;success_seen<=0;
        end else begin
            complete<=0;
            if(control_start)begin
                tx_state<=TX_WAIT;active<=1;error<=0;accepted_pixels<=0;success_seen<=0;
            end else if(active && !source_reset)begin
                case(tx_state)
                    TX_WAIT:tx_state<=TX_START;
                    TX_START:if(input_wr_ready)tx_state<=TX_DATA;
                    TX_DATA:if(input_wr_ready && !byte_valid && end_valid)tx_state<=TX_ERROR;
                    TX_ERROR:if(input_wr_ready)tx_state<=TX_STOP;
                    TX_STOP:tx_state<=TX_STOP;
                    default:begin error<=3;active<=0;end
                endcase
                if(status_capture_pending && !status_captured)begin
                    // The status arrived. The held error separately disables
                    // active/pixel_valid/complete on the very same edge.
                    success_seen<=1;
                    if(status_error!=0)begin error<=status_error;active<=0;end
                end
                if(pixel_valid && pixel_ready)accepted_pixels<=accepted_pixels+1'b1;
                if(success_seen && error==0 && (accepted_pixels==FRAME_PIXELS ||
                    (accepted_pixels==FRAME_PIXELS-1 && pixel_valid && pixel_ready)))begin
                    complete<=1;active<=0;
                end
            end
        end
    end
endmodule
