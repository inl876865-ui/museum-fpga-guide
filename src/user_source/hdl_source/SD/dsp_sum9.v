`timescale 1ns/1ps
// Exact sum encoded through a combinational unsigned EG4 multiplier.
// This is a multiplier use, not a native DSP add/ALU mode.
module dsp_sum9 (
    input wire [8:0] a,b,
    output wire [9:0] sum
);
    wire [35:0] product;
    EG_PHY_MULT18 #(
        .MODE("MULT18X18C"),
        .INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),.OUTPUTREG("DISABLE"),
        .SIGNEDAMUX("0"),.SIGNEDBMUX("0"),
        .SOURCEAMUX("1"),.SOURCEBMUX("1"),
        .CEAMUX("0"),.CEBMUX("0"),.CEPDMUX("0"),.CLKMUX("0"),
        .RSTANMUX("1"),.RSTBNMUX("1"),.RSTPDNMUX("1")
    ) u_multiplier (
        .a({a,b}),.b(18'd513),.p(product),
        .signeda(1'b0),.signedb(1'b0),.sourcea(1'b1),.sourceb(1'b1),
        .acin(),.bcin(),.acout(),.bcout(),
        .cea(1'b0),.ceb(1'b0),.cepd(1'b0),.clk(1'b0),
        .rstan(1'b1),.rstbn(1'b1),.rstpdn(1'b1)
    );
    assign sum={product[18]^a[0],product[17:9]};
endmodule
