`timescale 1ns/1ps
// Reference-clock-domain startup qualifier. Loss of either lock asserts reset
// immediately, even if a generated clock stops. Releasing reset requires both
// locks to be synchronized and stable, followed by each domain's reset chain.
// This reset MUST NOT drive PLL reset: a PLL must run before it can lock.
module pll_startup_guard #(
    parameter integer LOCK_STABLE_CYCLES = 16
) (
    input wire clk,
    input wire rst_n,
    input wire power_on_done,
    input wire sys_pll_lock,
    input wire video_pll_lock,
    output wire rst_all
);
    wire locks_available = rst_n && power_on_done && sys_pll_lock && video_pll_lock;
    (* async_reg = "true" *) reg [1:0] lock_sync = 2'b00;
    localparam integer COUNT_WIDTH = (LOCK_STABLE_CYCLES < 2) ? 1 : $clog2(LOCK_STABLE_CYCLES);
    reg [COUNT_WIDTH-1:0] lock_count = 0;
    reg lock_qualified = 1'b0;

    always @(posedge clk or negedge locks_available) begin
        if (!locks_available) begin
            lock_sync <= 0;
            lock_count <= 0;
            lock_qualified <= 0;
        end else begin
            lock_sync <= {lock_sync[0], 1'b1};
            if (!lock_sync[1]) begin
                lock_count <= 0;
                lock_qualified <= 0;
            end else if (!lock_qualified) begin
                if (lock_count == LOCK_STABLE_CYCLES-1)
                    lock_qualified <= 1;
                else
                    lock_count <= lock_count + 1'b1;
            end
        end
    end
    assign rst_all = !locks_available || !lock_qualified;
endmodule
