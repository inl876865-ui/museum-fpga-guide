`timescale 1ns/1ps
// Exact unsigned 32x32 upper product. One registered DSP evaluates all four
// half products; public input capture and 32-clock completion remain unchanged.
module caption_multiply (
    input wire clk,rst,start,
    input wire [31:0] samples,step_q32,
    output reg busy,done,
    output reg [31:0] pixels
);
    wire capture=start && !busy;
    reg [4:0] count;
    reg [31:0] samples_hold,step_hold;
    reg [15:0] p00_high;
    reg [31:0] p01,p10;
    wire [31:0] p00={p00_high,16'd0};
    // Shared DSP output holds p11 after count2; only then is the sum consumed.
    wire [31:0] p11;
    wire [15:0] operand_a=busy ? (count==0 ? samples_hold[15:0] : samples_hold[31:16]) : samples[15:0];
    wire [15:0] operand_b=busy ? (count==1 ? step_hold[15:0] : step_hold[31:16]) : step_q32[15:0];
    wire product_capture=capture || (busy && count<3);
    caption_dsp16_registered_product u_low_low(.clk(clk),.rst(rst),.capture(product_capture),.a(operand_a),.b(operand_b),.product(p11));
    // Include the carry from the low cross-half sum; dropping it would corrupt
    // the upper product even though the low 32 result bits are not published.
    wire [17:0] cross_low={2'd0,p00[31:16]}+{2'd0,p01[15:0]}+{2'd0,p10[15:0]};
    wire [17:0] cross_high={2'd0,p01[31:16]}+{2'd0,p10[31:16]}+{16'd0,cross_low[17:16]};
    wire [31:0] upper_product=p11+{14'd0,cross_high};
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            count<=0;busy<=0;done<=0;pixels<=0;
            samples_hold<=0;step_hold<=0;p00_high<=0;p01<=0;p10<=0;
        end
        else begin
            done<=0;
            if(start && !busy) begin
                count<=0;busy<=1;samples_hold<=samples;step_hold<=step_q32;
            end
            else if(busy) begin
                if(count==0) p00_high<=p11[31:16];
                else if(count==1) p01<=p11;
                else if(count==2) p10<=p11;
                if(count==31) begin pixels<=upper_product;busy<=0;done<=1;end
                else count<=count+1'b1;
            end
        end
    end
endmodule

module caption_dsp16_registered_product (
    input wire clk,rst,capture,
    input wire [15:0] a,b,
    output wire [31:0] product
);
    wire [35:0] full_product;
    EG_PHY_MULT18 #(
        .MODE("MULT18X18C"),
        .INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),.OUTPUTREG("ENABLE"),.SRMODE("ASYNC"),
        .SIGNEDAMUX("0"),.SIGNEDBMUX("0"),.SOURCEAMUX("1"),.SOURCEBMUX("1"),
        .CEAMUX("0"),.CEBMUX("0"),.CEPDMUX("SIG"),.CLKMUX("SIG"),
        .RSTANMUX("1"),.RSTBNMUX("1"),.RSTPDNMUX("SIG")
    ) u_multiplier (
        .a({2'd0,a}),.b({2'd0,b}),.p(full_product),
        .signeda(1'b0),.signedb(1'b0),.sourcea(1'b1),.sourceb(1'b1),
        .acin(18'd0),.bcin(18'd0),.acout(),.bcout(),
        .cea(1'b0),.ceb(1'b0),.cepd(capture),.clk(clk),
        .rstan(1'b1),.rstbn(1'b1),.rstpdn(!rst)
    );
    assign product=full_product[31:0];
endmodule
