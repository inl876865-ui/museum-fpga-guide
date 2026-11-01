`timescale 1ns/1ps
// Physical KEY2: plus/next, KEY3: minus/previous, KEY4: mode.
module player_key_control #(
    parameter integer CLK_FREQ_HZ = 100000000,
    parameter integer LONG_PRESS_MS = 500,
    parameter integer REPEAT_MS = 50,
    parameter integer MENU_TIMEOUT_MS = 3000
) (
    input wire clk, rst,
    input wire key_plus_n, key_minus_n, key_mode_n,
    output reg next_event, prev_event, auto_event,
    output reg auto_value,
    output reg [7:0] volume,
    output reg volume_mode,
    output reg period_mode,
    output reg fade_mode,
    output reg [1:0] fade_level,
    output reg [5:0] period_sec,
    output reg period_change_valid,
    output reg save_mode,
    output reg auto_mode,
    output reg source_mode,
    output reg track_mode,
    output reg source_wav,
    output reg track_next_event,
    output reg track_prev_event,
    output reg save_event,
    input wire save_busy,
    input wire restore_valid,
    input wire [7:0] restore_volume,
    input wire restore_period_valid,
    input wire [5:0] restore_period_sec,
    input wire [1:0] restore_fade_level
);
    wire plus_short, plus_long, minus_short, minus_long, mode_short;
    wire plus_n, minus_n, mode_n;
    key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .LONG_PRESS_MS(LONG_PRESS_MS)) u_plus (
        .clk(clk), .rst(rst), .button_in(key_plus_n),
        .button_stable_out(plus_n), .short_press(plus_short), .long_press(plus_long)
    );
    key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .LONG_PRESS_MS(LONG_PRESS_MS)) u_minus (
        .clk(clk), .rst(rst), .button_in(key_minus_n),
        .button_stable_out(minus_n), .short_press(minus_short), .long_press(minus_long)
    );
    key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .LONG_PRESS_MS(LONG_PRESS_MS)) u_mode (
        .clk(clk), .rst(rst), .button_in(key_mode_n),
        .button_stable_out(mode_n), .short_press(mode_short), .long_press()
    );
    localparam integer REPEAT_CYCLES = (CLK_FREQ_HZ / 1000) * REPEAT_MS;
    localparam integer MENU_TIMEOUT_CYCLES = (CLK_FREQ_HZ / 1000) * MENU_TIMEOUT_MS;
    reg plus_repeat, minus_repeat, blocked;
    reg [31:0] plus_count, minus_count;
    reg [31:0] menu_idle_count;
    reg [2:0] release_count;
    wire menu_active = source_mode || track_mode || auto_mode ||
                       volume_mode || fade_mode || period_mode || save_mode;
    wire plus_tick = plus_repeat && !plus_n && plus_count == REPEAT_CYCLES-1;
    wire minus_tick = minus_repeat && !minus_n && minus_count == REPEAT_CYCLES-1;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            volume <= 8'd128;
            volume_mode <= 1'b0;
            period_mode <= 1'b0;
            fade_mode <= 1'b0;
            fade_level <= 2'd1;
            period_sec <= 6'd3;
            period_change_valid <= 1'b0;
            save_mode <= 0; save_event <= 0;
            auto_mode <= 0; auto_value <= 0;
            source_mode <= 0; track_mode <= 0; source_wav <= 1;
            track_next_event <= 0; track_prev_event <= 0;
            next_event <= 0; prev_event <= 0; auto_event <= 0;
            plus_repeat <= 0; minus_repeat <= 0;
            plus_count <= 0; minus_count <= 0;
            menu_idle_count <= 0;
            blocked <= 1; release_count <= 0;
        end else begin
            save_event <= 0;
            if (restore_valid) volume <= restore_volume;
            if (restore_valid) fade_level <= restore_fade_level;
            period_change_valid <= 0;
            if (restore_period_valid) begin
                period_sec <= restore_period_sec < 1 ? 6'd1 :
                              restore_period_sec > 30 ? 6'd30 : restore_period_sec;
                period_change_valid <= 1;
            end
            next_event <= 0; prev_event <= 0; auto_event <= 0;
            track_next_event <= 0; track_prev_event <= 0;
            // Mode has priority. Drain release pulses before rearming keys.
            if (mode_short && !save_busy) begin
                if (save_mode) save_mode <= 0;
                else if (period_mode) begin period_mode <= 0; save_mode <= 1; end
                else if (fade_mode) begin fade_mode <= 0; period_mode <= 1; end
                else if (volume_mode) begin volume_mode <= 0; fade_mode <= 1; end
                else if (auto_mode) begin auto_mode <= 0; volume_mode <= 1; end
                else if (track_mode) begin track_mode <= 0; auto_mode <= 1; end
                else if (source_mode) begin
                    source_mode <= 0;
                    if (source_wav) track_mode <= 1;
                    else auto_mode <= 1;
                end else source_mode <= 1;
            end
            if (save_busy || !mode_n || mode_short || (!plus_n && !minus_n)) begin
                blocked <= 1;
                release_count <= 0;
                plus_repeat <= 0; minus_repeat <= 0;
                plus_count <= 0; minus_count <= 0;
            end else if (blocked) begin
                if (plus_n && minus_n && mode_n) begin
                    if (release_count == 7) blocked <= 0;
                    else release_count <= release_count + 1'b1;
                end else release_count <= 0;
            end else if (source_mode) begin
                if (plus_short && !minus_short) source_wav <= 1;
                else if (minus_short && !plus_short) source_wav <= 0;
                plus_repeat <= 0; minus_repeat <= 0;
                plus_count <= 0; minus_count <= 0;
            end else if (track_mode) begin
                track_next_event <= plus_short && !minus_short;
                track_prev_event <= minus_short && !plus_short;
                plus_repeat <= 0; minus_repeat <= 0;
                plus_count <= 0; minus_count <= 0;
            end else if (auto_mode) begin
                if (plus_short || minus_short) begin
                    auto_event <= 1;
                    auto_value <= plus_short;
                end
                plus_repeat <= 0; minus_repeat <= 0;
                plus_count <= 0; minus_count <= 0;
            end else if (save_mode) begin
                save_event <= plus_short;
                plus_repeat <= 0; minus_repeat <= 0;
                plus_count <= 0; minus_count <= 0;
            end else if (!volume_mode && !period_mode && !fade_mode) begin
                next_event <= plus_short;
                prev_event <= minus_short;
                plus_repeat <= 0; minus_repeat <= 0;
                plus_count <= 0; minus_count <= 0;
            end else begin
                if (plus_n) begin plus_repeat <= 0; plus_count <= 0; end
                else if (plus_long) begin plus_repeat <= 1; plus_count <= 0; end
                else if (plus_repeat) begin
                    if (plus_tick) plus_count <= 0;
                    else plus_count <= plus_count + 1'b1;
                end
                if (minus_n) begin minus_repeat <= 0; minus_count <= 0; end
                else if (minus_long) begin minus_repeat <= 1; minus_count <= 0; end
                else if (minus_repeat) begin
                    if (minus_tick) minus_count <= 0;
                    else minus_count <= minus_count + 1'b1;
                end
                if ((plus_short || plus_long || plus_tick) &&
                    !(minus_short || minus_long || minus_tick)) begin
                    if (fade_mode) begin
                        if (fade_level < 3) fade_level <= fade_level + 1'b1;
                    end else if (period_mode) begin
                        if (period_sec < 30) begin
                            period_sec <= period_sec + 1'b1;
                            period_change_valid <= 1;
                        end
                    end else if (volume != 255) volume <= volume + 1'b1;
                end else if ((minus_short || minus_long || minus_tick) &&
                             !(plus_short || plus_long || plus_tick)) begin
                    if (fade_mode) begin
                        if (fade_level > 0) fade_level <= fade_level - 1'b1;
                    end else if (period_mode) begin
                        if (period_sec > 1) begin
                            period_sec <= period_sec - 1'b1;
                            period_change_valid <= 1;
                        end
                    end else if (volume != 0) volume <= volume - 1'b1;
                end
            end
            if (!menu_active || save_busy || !plus_n || !minus_n || !mode_n ||
                plus_short || minus_short || mode_short || plus_long || minus_long) begin
                menu_idle_count <= 0;
            end else if (menu_idle_count == MENU_TIMEOUT_CYCLES-1) begin
                menu_idle_count <= 0;
                source_mode <= 0; track_mode <= 0;
                auto_mode <= 0; volume_mode <= 0; fade_mode <= 0;
                period_mode <= 0; save_mode <= 0;
                blocked <= 1; release_count <= 0;
                plus_repeat <= 0; minus_repeat <= 0;
                plus_count <= 0; minus_count <= 0;
            end else menu_idle_count <= menu_idle_count + 1'b1;
        end
    end
endmodule
