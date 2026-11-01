// Dedicated SD clock, 50 MHz -> 50 MHz. Manual EG_PHY_PLL wrapper.
// REF=5, FB=5, C0=16: PFD=10 MHz, VCO=800 MHz, external C0 feedback.
// Analog loop coefficients retained from the existing sys_pll template.
// Verified by TD 6.2.168116 derive_clocks/route/DRC and vendor functional model.
// Functional simulation does not characterize analog lock/jitter; board validation required.
`timescale 1 ns / 100 fs

module sd_pll (
  refclk,
  reset,
  clk0_out,
  extlock
);

  input refclk;
  input reset;
  output clk0_out;
  output extlock; // Included in the common startup lock qualification

  wire clk0_buf;

  EG_LOGIC_BUFG bufg_feedback (
    .i(clk0_buf),
    .o(clk0_out) 
  );

  EG_PHY_PLL #(
    .DPHASE_SOURCE("DISABLE"),
    .DYNCFG("DISABLE"),
    .FIN("50.000000"),
    .FEEDBK_MODE("NORMAL"),
    .FEEDBK_PATH("CLKC0_EXT"),
    .STDBY_ENABLE("DISABLE"),
    .PLLRST_ENA("ENABLE"),
    .SYNC_ENABLE("DISABLE"),
    .GMC_GAIN(2),
    .ICP_CURRENT(24),
    .KVCO(2),
    .LPF_CAPACITOR(1),
    .LPF_RESISTOR(4),
    .REFCLK_DIV(5),
    .FBCLK_DIV(5),
    .CLKC0_ENABLE("ENABLE"),
    .CLKC0_DIV(16),
    .CLKC0_CPHASE(15),
    .CLKC0_FPHASE(0),
    .CLKC1_ENABLE("DISABLE"),
    .CLKC1_DIV(25),
    .CLKC1_CPHASE(24),
    .CLKC1_FPHASE(0),
    .CLKC2_ENABLE("DISABLE"),
    .CLKC2_DIV(25),
    .CLKC2_CPHASE(11),
    .CLKC2_FPHASE(0) 
  ) pll_inst (
    .refclk(refclk),
    .reset(reset),
    .stdby(1'b0),
    .extlock(extlock),
    .load_reg(1'b0),
    .psclk(1'b0),
    .psdown(1'b0),
    .psstep(1'b0),
    .psclksel(3'b000),
    .psdone(open),
    .dclk(1'b0),
    .dcs(1'b0),
    .dwe(1'b0),
    .di(8'b00000000),
    .daddr(6'b000000),
    .do({open, open, open, open, open, open, open, open}),
    .fbclk(clk0_out),
    .clkc({open, open, open, open, clk0_buf}) 
  );

endmodule

