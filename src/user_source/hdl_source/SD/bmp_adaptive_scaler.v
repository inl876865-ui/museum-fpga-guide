`timescale 1ns/1ps
// BMP24 input, centered nearest-neighbor fit, fixed bottom-up output frame.
// A byte-organized target row uses two BRAM9K blocks, independent of source width.
module bmp_adaptive_scaler #(
    parameter integer FRAME_WIDTH=640,
    parameter integer FRAME_HEIGHT=480
)(
    input wire clk,rst,start,
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
    output reg [2:0] error,
    output wire [15:0] source_width,source_height
);
    localparam INPUT_BYTES=0,CHECK_HEADER=1,MULTIPLY=2,CHECK_EXTENT=3,
        FIT_DIVIDE=4,LAYOUT=5,CAPTURE_PIXEL=6,STORE_B=7,STORE_G=8,STORE_R=9,
        ROW_DONE=10,ROW_ADVANCE=11,PREPARE_PIXEL=12,
        READ_B_WAIT=13,READ_B=14,READ_G_WAIT=15,READ_G=16,
        READ_R_WAIT=17,READ_R=18,SEND_PIXEL=19,BLACK_ROW=20,FINISHED=21,WAIT_DRAIN=22,
        CHECK_HEADER_BUDGET=23;
    reg [4:0] state;
    // Dedicated25MHz domain: one algorithm step per actual clock.
    // Approved first-version input limit: each dimension1..4096, file<=16MiB.
    reg [12:0] width_value,height_value;
    assign source_width={3'd0,width_value};
    assign source_height={3'd0,height_value};
    reg [24:0] byte_position;
    reg [12:0] source_rows_left;
    reg [24:0] declared_size,pixel_offset;
    // DIB validation finishes before the same work register computes the fit.
    reg [25:0] header_work;
    wire [24:0] dib=header_work[24:0];
    reg [12:0] fit_denominator;
    localparam integer FIT_BITS=$clog2(4096*((FRAME_WIDTH>FRAME_HEIGHT)?FRAME_WIDTH:FRAME_HEIGHT)+1);
    wire [FIT_BITS-1:0] fit_remainder=header_work[FIT_BITS-1:0];
    // The four mutually-exclusive subtraction uses share one physical path.
    // Keep each original borrow/truncation view and all existing register widths.
    localparam integer SUBTRACT_BITS=(FIT_BITS+1>26)?FIT_BITS+1:26;
    wire [SUBTRACT_BITS-1:0] subtract_operand_a=state==CHECK_HEADER ? {1'b0,pixel_offset} :
        state==CHECK_HEADER_BUDGET ? {1'b0,declared_size} :
        state==FIT_DIVIDE ? fit_remainder : header_work;
    wire [SUBTRACT_BITS-1:0] subtract_operand_b=state==CHECK_HEADER ? {1'b0,dib} :
        state==CHECK_HEADER_BUDGET ? {1'b0,pixel_offset} :
        state==FIT_DIVIDE ? fit_denominator : stride;
    wire [SUBTRACT_BITS-1:0] subtract_difference=subtract_operand_a-subtract_operand_b;
    wire [FIT_BITS:0] fit_difference=subtract_difference[FIT_BITS:0];
    wire [25:0] header_budget=subtract_difference[25:0];
    wire [25:0] dib_room=subtract_difference[25:0];
    reg pixel_started;
    reg format_bad,dimension_bad,accepted,output_done;
    reg [5:0] header_position;
    reg [14:0] stride;
    reg [12:0] row_pixels_left;
    reg [1:0] padding_left;
    wire [14:0] source_row_bytes=({2'b0,width_value}<<1)+{2'b0,width_value};
    reg [1:0] phase;
    // Input-pixel replication and output-row replay run in exclusive states.
    reg [23:0] source_pixel;
    reg last_byte_of_row;
    // Validate stride*height by spending one stride per source row.
    // The existing work register holds the remaining header-declared budget.
    // A borrow is caught within two work steps, before arithmetic can wrap.
    reg extent_overflow;

    reg [9:0] fit_quotient,fit_width,fit_height,pad_left,pad_bottom;
    reg fit_by_width;
    function integer common_factor;
        input integer a,b;
        integer r;
        begin
            while(b!=0)begin r=a%b;a=b;b=r;end
            common_factor=a;
        end
    endfunction
    localparam integer FIT_COMMON=common_factor(FRAME_WIDTH,FRAME_HEIGHT);
    wire by_width=source_width*(FRAME_HEIGHT/FIT_COMMON)>=source_height*(FRAME_WIDTH/FIT_COMMON);

    // Signed residuals implement floor((2*x+1)*W/(2*Dw)). For bottom-up Y use
    // floor(((2*y+1)*H-1)/(2*Dh)), preserving the top-down tie convention.
    reg signed [14:0] x_error,y_error;
    reg [9:0] captured_columns,content_rows,frame_x,frame_y;
    reg [10:0] store_address,read_address;
    (* ram_style="bram" *) reg [7:0] row_memory[0:2047];
    reg [7:0] row_byte_q;
    wire capture_row=content_rows<fit_height && y_error>0;
    // Select operands before the add/sub unit; preserve every existing state edge.
    wire x_initial=state==LAYOUT || state==ROW_ADVANCE;
    wire [14:0] x_operand_a=x_initial ? {4'd0,fit_width,1'b0} : x_error;
    wire [14:0] x_operand_b=x_initial ? {2'd0,width_value} :
        state==STORE_R ? {1'b0,width_value,1'b0} : {4'd0,fit_width,1'b0};
    wire x_subtract=x_initial || state==STORE_R;
    wire y_initial=state==LAYOUT;
    wire [14:0] y_operand_a=y_initial ? {4'd0,fit_height,1'b1} : y_error;
    wire [14:0] y_operand_b=y_initial ? {2'd0,height_value} :
        state==ROW_ADVANCE ? {4'd0,fit_height,1'b0} : {1'b0,height_value,1'b0};
    wire y_subtract=state!=ROW_ADVANCE;
    wire signed [14:0] x_residual_result,y_residual_result;
    wire [14:0] x_complement_b=x_operand_b^{15{x_subtract}};
    wire [15:0] x_packed_sum={x_operand_a,x_subtract}+{x_complement_b,1'b1};
    assign x_residual_result=x_packed_sum[15:1];
    wire [14:0] y_complement_b=y_operand_b^{15{y_subtract}};
    wire [15:0] y_packed_sum={y_operand_a,y_subtract}+{y_complement_b,1'b1};
    assign y_residual_result=y_packed_sum[15:1];
    wire signed [14:0] next_y_error=y_residual_result;
    assign byte_ready=state==INPUT_BYTES && !complete && error==0;
    wire core_pixel_valid=state==SEND_PIXEL || state==BLACK_ROW;
    wire [23:0] core_pixel=state==BLACK_ROW ? 24'd0 : source_pixel;
    assign pixel_valid=core_pixel_valid && error==0;
    assign pixel=core_pixel;

    always @(posedge clk) begin
        row_byte_q<=row_memory[read_address];
        if(state==STORE_B || state==STORE_G || state==STORE_R)
            row_memory[store_address]<=state==STORE_B ? source_pixel[7:0] :
                state==STORE_G ? source_pixel[15:8] : source_pixel[23:16];
    end

    always @(posedge clk) begin
        if(rst || start) begin
            state<=INPUT_BYTES;byte_position<=0;source_rows_left<=0;
            declared_size<=0;pixel_offset<=0;header_work<=0;pixel_started<=0;
            width_value<=0;height_value<=0;format_bad<=0;dimension_bad<=0;
            accepted<=0;output_done<=0;header_position<=0;
            row_pixels_left<=0;padding_left<=0;stride<=0;phase<=0;
            source_pixel<=0;last_byte_of_row<=0;
            extent_overflow<=0;
            fit_denominator<=0;fit_quotient<=0;
            fit_width<=0;fit_height<=0;pad_left<=0;pad_bottom<=0;fit_by_width<=0;
            x_error<=0;y_error<=0;
            captured_columns<=0;content_rows<=0;frame_x<=0;frame_y<=0;
            store_address<=0;read_address<=0;
            complete<=0;error<=0;
        end else begin
            complete<=0;
            case(state)
                INPUT_BYTES: begin
                    if(byte_valid) begin
                        byte_position<=byte_position+1'b1;
                        if(byte_position==file_size) begin error<=3;state<=FINISHED;end
                        if(header_position<54) begin
                            header_position<=header_position+1'b1;
                            case(header_position)
                                0:if(byte_data!=8'h42) format_bad<=1;
                                1:if(byte_data!=8'h4d) format_bad<=1;
                                2:declared_size[7:0]<=byte_data;
                                3:declared_size[15:8]<=byte_data;
                                4:declared_size[23:16]<=byte_data;
                                5:begin declared_size[24]<=byte_data[0];if(|byte_data[7:1]) format_bad<=1;end
                                10:pixel_offset[7:0]<=byte_data;
                                11:pixel_offset[15:8]<=byte_data;
                                12:pixel_offset[23:16]<=byte_data;
                                13:begin pixel_offset[24]<=byte_data[0];if(|byte_data[7:1]) format_bad<=1;end
                                14:header_work[7:0]<=byte_data;15:header_work[15:8]<=byte_data;
                                16:header_work[23:16]<=byte_data;17:begin header_work[24]<=byte_data[0];if(|byte_data[7:1]) format_bad<=1;end
                                18:width_value[7:0]<=byte_data;19:begin width_value[12:8]<=byte_data[4:0];if(|byte_data[7:5])dimension_bad<=1;end
                                20,21,24,25:if(byte_data!=0) dimension_bad<=1;
                                22:height_value[7:0]<=byte_data;23:begin height_value[12:8]<=byte_data[4:0];if(|byte_data[7:5])dimension_bad<=1;end
                                26:if(byte_data!=1) format_bad<=1;
                                27,29,30,31,32,33:if(byte_data!=0) format_bad<=1;
                                28:if(byte_data!=24) format_bad<=1;
                                53:state<=CHECK_HEADER;
                            endcase
                        end else if(accepted && (pixel_started || byte_position==pixel_offset) && source_rows_left!=0) begin
                            pixel_started<=1;
                            if(row_pixels_left!=0) begin
                                case(phase)
                                    0:begin source_pixel[7:0]<=byte_data;phase<=1;end
                                    1:begin source_pixel[15:8]<=byte_data;phase<=2;end
                                    2:begin
                                        source_pixel[23:16]<=byte_data;phase<=0;
                                        row_pixels_left<=row_pixels_left-1'b1;
                                        last_byte_of_row<=row_pixels_left==1 && width_value[1:0]==0;
                                        state<=CAPTURE_PIXEL;
                                    end
                                endcase
                            end else if(padding_left==1) begin padding_left<=0;state<=ROW_DONE;end
                            else padding_left<=padding_left-1'b1;
                        end
                    end else if(end_valid) begin
                        if(end_error!=0)begin
                            complete<=1;state<=FINISHED;error<=end_error==8'h10 ? 2 : 3;
                        end else if(!accepted || byte_position!=file_size || source_rows_left!=0 || phase!=0 || !output_done)begin
                            complete<=1;state<=FINISHED;error<=3;
                        end else state<=WAIT_DRAIN;
                    end
                end
                CHECK_HEADER: begin
                    if(format_bad || dimension_bad || source_width==0 || source_height==0 || source_width>4096 || source_height>4096 ||
                       dib<40 || dib_room[25] || dib_room[24:0]<14 || pixel_offset<54 ||
                       file_size<54 || file_size>16777216 || declared_size>file_size) begin
                        error<=1;state<=FINISHED;
                    end else state<=CHECK_HEADER_BUDGET;
                end
                // One additional25MHz header cycle; pixel/row states unchanged.
                CHECK_HEADER_BUDGET: begin
                    if(header_budget[25])begin error<=1;state<=FINISHED;end
                    else begin
                        stride<=(source_row_bytes+15'd3)&15'h7ffc;
                        declared_size<=header_budget[24:0];
                        header_work<={1'b0,header_budget[24:0]};
                        source_rows_left<=height_value;state<=MULTIPLY;
                    end
                end
                MULTIPLY: begin
                    if(extent_overflow) begin error<=1;state<=FINISHED;end
                    else begin
                        header_work<=subtract_difference[25:0];
                        extent_overflow<=header_work[25];
                        source_rows_left<=source_rows_left-1'b1;
                        if(source_rows_left==1)state<=CHECK_EXTENT;
                    end
                end
                CHECK_EXTENT: begin
                    if(extent_overflow || header_work[25]) begin error<=1;state<=FINISHED;end
                    else begin
                        accepted<=1;
                        fit_by_width<=by_width;
                        if(by_width) begin
                            fit_width<=FRAME_WIDTH;header_work<=source_height*FRAME_WIDTH;fit_denominator<=source_width;
                        end else begin
                            fit_height<=FRAME_HEIGHT;header_work<=source_width*FRAME_HEIGHT;fit_denominator<=source_height;
                        end
                        fit_quotient<=0;state<=FIT_DIVIDE;
                    end
                end
                FIT_DIVIDE: begin
                    if(!fit_difference[FIT_BITS]) begin
                        header_work<=fit_difference[FIT_BITS-1:0];fit_quotient<=fit_quotient+1'b1;
                    end else begin
                        if(fit_by_width) fit_height<=fit_quotient==0 ? 10'd1 : fit_quotient;
                        else fit_width<=fit_quotient==0 ? 10'd1 : fit_quotient;
                        state<=LAYOUT;
                    end
                end
                LAYOUT: begin
                    source_rows_left<=height_value;
                    row_pixels_left<=width_value;padding_left<=width_value[1:0];
                    pad_left<=(FRAME_WIDTH-fit_width)>>1;
                    pad_bottom<=FRAME_HEIGHT-fit_height-((FRAME_HEIGHT-fit_height)>>1);
                    x_error<=x_residual_result;
                    y_error<=y_residual_result;
                    if(FRAME_HEIGHT!=fit_height) state<=BLACK_ROW;else state<=INPUT_BYTES;
                end
                CAPTURE_PIXEL: begin
                    if(capture_row && captured_columns<fit_width && x_error>0) state<=STORE_B;
                    else begin
                        x_error<=x_residual_result;
                        state<=last_byte_of_row ? ROW_DONE : INPUT_BYTES;
                    end
                end
                STORE_B:begin store_address<=store_address+11'd1;state<=STORE_G;end
                STORE_G:begin store_address<=store_address+11'd1;state<=STORE_R;end
                STORE_R:begin
                    store_address<=store_address+11'd1;captured_columns<=captured_columns+1'b1;
                    x_error<=x_residual_result;state<=CAPTURE_PIXEL;
                end
                ROW_DONE: begin
                    if(capture_row) begin
                        if(captured_columns!=fit_width) begin error<=3;state<=FINISHED;end
                        else begin frame_x<=0;read_address<=0;state<=PREPARE_PIXEL;end
                    end else state<=ROW_ADVANCE;
                end
                ROW_ADVANCE: begin
                    source_rows_left<=source_rows_left-1'b1;
                    row_pixels_left<=width_value;padding_left<=width_value[1:0];
                    y_error<=y_residual_result;
                    x_error<=x_residual_result;
                    store_address<=0;captured_columns<=0;state<=INPUT_BYTES;
                end
                PREPARE_PIXEL: begin
                    if(frame_x<pad_left || frame_x>=pad_left+fit_width) begin source_pixel<=0;state<=SEND_PIXEL;end
                    else begin state<=READ_B_WAIT;end
                end
                READ_B_WAIT:state<=READ_B;
                READ_B:begin source_pixel[7:0]<=row_byte_q;read_address<=read_address+11'd1;state<=READ_G_WAIT;end
                READ_G_WAIT:state<=READ_G;
                READ_G:begin source_pixel[15:8]<=row_byte_q;read_address<=read_address+11'd1;state<=READ_R_WAIT;end
                READ_R_WAIT:state<=READ_R;
                READ_R:begin source_pixel[23:16]<=row_byte_q;read_address<=read_address+11'd1;state<=SEND_PIXEL;end
                SEND_PIXEL:if(pixel_ready) begin
                    if(frame_x==FRAME_WIDTH-1) begin
                        frame_x<=0;frame_y<=frame_y+1'b1;content_rows<=content_rows+1'b1;
                        y_error<=next_y_error;read_address<=0;
                        if(content_rows+1'b1==fit_height) begin
                            if(frame_y+1'b1==FRAME_HEIGHT) begin output_done<=1;state<=ROW_ADVANCE;end
                            else state<=BLACK_ROW;
                        end else if(next_y_error>0) state<=PREPARE_PIXEL;
                        else state<=ROW_ADVANCE;
                    end else begin frame_x<=frame_x+1'b1;state<=PREPARE_PIXEL;end
                end
                BLACK_ROW:if(pixel_ready) begin
                    if(frame_x==FRAME_WIDTH-1) begin
                        frame_x<=0;frame_y<=frame_y+1'b1;
                        if(frame_y+1'b1==FRAME_HEIGHT) begin output_done<=1;state<=ROW_ADVANCE;end
                        else if(frame_y+1'b1==pad_bottom) state<=INPUT_BYTES;
                    end else frame_x<=frame_x+1'b1;
                end
                WAIT_DRAIN:begin complete<=1;state<=FINISHED;end
                FINISHED:state<=FINISHED;
                default:begin error<=3;state<=FINISHED;end
            endcase
        end
    end
endmodule
