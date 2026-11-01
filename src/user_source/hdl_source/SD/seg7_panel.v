`timescale 1ns/1ps

// R3a: 8-digit 7-segment front panel (docs/29). Shows three pages that auto
// rotate every two seconds - picture number, volume, slideshow period - and any
// parameter event forces its page for the hold window. Pin map and drive
// polarity follow the official 2026 demo examples (5_seg_SCAN /
// 18_sd_card_audio): digit selects are active-low one-hot, segments are
// active-low with bit0=A..bit6=G and bit7=decimal point; scan step is 8192
// clock cycles per digit (1.31 ms frame at 50 MHz, same cadence as the demo).
//
// Pages (digit 7 = leftmost):
//   PIC:  P I C _ _ _ _ n     n = 1..4
//   VOL:  V O L _ _ _ d d d     volume 0..255 in decimal
//   PRD:  P R d _ _ _ d d (leading zero blanked)     period seconds and unit
module seg7_panel #(
    parameter integer CLK_HZ = 50000000,
    parameter integer IMAGE_BITS=2,
    parameter integer SCAN_STEP_CYCLES = 8192,
    parameter integer PAGE_PERIOD_CYCLES = 100000000, // 2 s rotation
    parameter integer HOLD_CYCLES = 100000000         // 2 s forced page
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    input  wire [2:0] error_code,    // 0: normal pages; nonzero: ERR code
    input  wire       picture_valid, // no committed picture: show dash
    input  wire [IMAGE_BITS-1:0] media_id,      // 0..3
    input  wire [7:0] volume,        // 0..255
    input  wire [5:0] period_sec,    // e.g. 2/5/10/30
    input  wire       save_mode,
    input  wire [1:0] save_status,
    input  wire       auto_mode,
    input  wire       source_mode,
    input  wire       track_mode,
    input  wire       source_wav,
    input  wire [3:0] track_number,
    input  wire       auto_enabled,
    input  wire       volume_mode,   // hold VOL while editing; errors still override
    input  wire       fade_mode,
    input  wire [1:0] fade_level,
    input  wire       period_mode,   // hold PRD while editing
    input  wire       pic_event,     // pulse: force PIC page
    input  wire       vol_event,     // pulse: force VOL page
    input  wire       prd_event,     // pulse: force PRD page
    output reg  [7:0] seg_n,         // {dp, g,f,e,d,c,b,a} active low
    output reg  [7:0] dig_n          // digit select, active low one-hot
);
    localparam [2:0] PAGE_PIC = 3'd0;
    localparam [2:0] PAGE_VOL = 3'd1;
    localparam [2:0] PAGE_PRD = 3'd2;

    localparam integer SCAN_WIDTH = (SCAN_STEP_CYCLES < 2) ? 1 : $clog2(SCAN_STEP_CYCLES);
    reg [SCAN_WIDTH-1:0] scan_cnt;
    reg [7:0] volume_q;
    reg [5:0] period_sec_q;
    reg [31:0] page_timer;
    reg [31:0] hold_timer;
    reg [2:0]  page;
    reg        holding;

    // -------- page selection: rotate, or hold the forced page --------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            volume_q <= volume;
            period_sec_q <= period_sec;
            page       <= PAGE_PIC;
            page_timer <= 32'd0;
            hold_timer <= 32'd0;
            holding    <= 1'b0;
        end else begin
            volume_q <= volume;
            period_sec_q <= period_sec;
            if (volume_mode || vol_event || volume != volume_q) begin
                page <= PAGE_VOL; holding <= 1'b1; hold_timer <= 32'd0; page_timer <= 32'd0;
            end else if (period_mode || prd_event || period_sec != period_sec_q) begin
                page <= PAGE_PRD; holding <= 1'b1; hold_timer <= 32'd0; page_timer <= 32'd0;
            end else if (pic_event) begin
                page <= PAGE_PIC; holding <= 1'b1; hold_timer <= 32'd0; page_timer <= 32'd0;
            end else if (holding) begin
                if (hold_timer >= HOLD_CYCLES - 1) begin
                    holding    <= 1'b0;
                    page_timer <= 32'd0;
                end else begin
                    hold_timer <= hold_timer + 1'b1;
                end
            end else begin
                if (page_timer >= PAGE_PERIOD_CYCLES - 1) begin
                    page_timer <= 32'd0;
                    if (page == PAGE_PRD)
                        page <= PAGE_PIC;
                    else
                        page <= page + 1'b1;
                end else begin
                    page_timer <= page_timer + 1'b1;
                end
            end
        end
    end

    // -------- decimal conversion (combinational double-dabble) --------
    // volume 0..255 -> three BCD digits; period <= 99 -> two digits
    function [11:0] bcd8;
        input [7:0] v;
        integer i;
        reg [19:0] sh;
        reg [3:0] n0, n1, n2;
        begin
            sh = {v, 12'd0};
            n0 = 4'd0; n1 = 4'd0; n2 = 4'd0;
            for (i = 0; i < 8; i = i + 1) begin
                if (n0 >= 5) n0 = n0 + 3;
                if (n1 >= 5) n1 = n1 + 3;
                if (n2 >= 5) n2 = n2 + 3;
                n2 = {n2[2:0], n1[3]};
                n1 = {n1[2:0], n0[3]};
                n0 = {n0[2:0], sh[19]};
                sh = {sh[18:0], 1'b0};
            end
            bcd8 = {n2, n1, n0};
        end
    endfunction

    wire [11:0] pic_bcd=bcd8({{(7-IMAGE_BITS){1'b0}},media_id}+8'd1);
    wire [11:0] vol_bcd = bcd8(volume);
    wire [11:0] prd_bcd = bcd8({2'b00, period_sec});
    wire [3:0] prd_tens = prd_bcd[7:4];
    wire [3:0] prd_ones = prd_bcd[3:0];

    // -------- active-high 7-seg font (bit0=A..bit6=G) --------
    function [6:0] seg_font;
        input [4:0] sym;
        begin
            case (sym)
                5'd0:    seg_font = 7'h3f;
                5'd1:    seg_font = 7'h06;
                5'd2:    seg_font = 7'h5b;
                5'd3:    seg_font = 7'h4f;
                5'd4:    seg_font = 7'h66;
                5'd5:    seg_font = 7'h6d;
                5'd6:    seg_font = 7'h7d;
                5'd7:    seg_font = 7'h07;
                5'd8:    seg_font = 7'h7f;
                5'd9:    seg_font = 7'h6f;
                5'd10:   seg_font = 7'h78;  // t
                5'd11:   seg_font = 7'h5c;  // o
                5'd12:   seg_font = 7'h54;  // n
                5'h10+0: seg_font = 7'h00;  // blank
                5'h10+1: seg_font = 7'h73;  // P
                5'h10+2: seg_font = 7'h06;  // I
                5'h10+3: seg_font = 7'h39;  // C
                5'h10+4: seg_font = 7'h3e;  // V
                5'h10+5: seg_font = 7'h38;  // L
                5'h10+6: seg_font = 7'h50;  // R
                5'h10+7: seg_font = 7'h5e;  // d
                5'h10+8: seg_font = 7'h6d;  // S
                5'h1b: seg_font = 7'h76;  // K approximated by H
                5'h1c: seg_font = 7'h71;  // F
                5'h1d: seg_font = 7'h77;  // A
                5'h1e: seg_font = 7'h7c;  // b
                5'h1f: seg_font = 7'h6e;  // Y
                5'h1a: seg_font = 7'h79;  // E
                5'h19: seg_font = 7'h40;  // dash
                default: seg_font = 7'h00;
            endcase
        end
    endfunction

    localparam [4:0] F_BLANK = 5'h10;
    localparam [4:0] F_P     = 5'h11;
    localparam [4:0] F_I     = 5'h12;
    localparam [4:0] F_C     = 5'h13;
    localparam [4:0] F_V     = 5'h14;
    localparam [4:0] F_L     = 5'h15;
    localparam [4:0] F_R     = 5'h16;
    localparam [4:0] F_D     = 5'h17;
    localparam [4:0] F_S     = 5'h18;

    // digit 0 = rightmost .. digit 7 = leftmost
    reg [4:0] symbols [0:7];
    integer d;
    always @* begin
        for (d = 0; d < 8; d = d + 1)
            symbols[d] = F_BLANK;
        case (page)
        PAGE_PIC: begin
            symbols[7] = F_P;
            symbols[6] = F_I;
            symbols[5] = F_C;
            symbols[1] = picture_valid && pic_bcd[7:4]!=0 ? {1'b0,pic_bcd[7:4]} : F_BLANK;
            symbols[0] = picture_valid ? {1'b0,pic_bcd[3:0]} : 5'h19;
        end
        PAGE_VOL: begin
            symbols[7] = F_V;
            symbols[6] = 5'd0;      // 'O' shares the zero glyph (0x3f)
            symbols[5] = F_L;
            symbols[2] = {1'b0, vol_bcd[11:8]};
            symbols[1] = {1'b0, vol_bcd[7:4]};
            symbols[0] = {1'b0, vol_bcd[3:0]};
        end
        PAGE_PRD: begin
            symbols[7] = F_P;
            symbols[6] = F_R;
            symbols[5] = F_D;
            symbols[1] = (prd_tens == 0) ? F_BLANK : {1'b0, prd_tens};
            symbols[0] = {1'b0, prd_ones};
        end
        default: ;
        endcase
        if (save_mode) begin
            for (d=0; d<8; d=d+1) symbols[d] = F_BLANK;
            case (save_status)
                0: begin // SAVE (V uses U glyph)
                    symbols[7]=F_S; symbols[6]=5'h1d; symbols[5]=F_V; symbols[4]=5'h1a;
                end
                1: begin // bUSY
                    symbols[7]=5'h1e; symbols[6]=F_V; symbols[5]=F_S; symbols[4]=5'h1f;
                end
                2: begin symbols[7]=0; symbols[6]=5'h1b; end // OK, K approximated
                3: begin
                    symbols[7]=5'h1c; symbols[6]=5'h1d; symbols[5]=F_I; symbols[4]=F_L;
                end
            endcase
        end
        if (auto_mode) begin
            for (d=0; d<8; d=d+1) symbols[d] = F_BLANK;
            symbols[7] = 5'h1d;   // A
            symbols[6] = F_V;     // U approximates u
            symbols[5] = 5'd10;   // t
            symbols[4] = 5'd11;   // o
            if (auto_enabled) begin
                symbols[1] = 5'd11; // o
                symbols[0] = 5'd12; // n
            end else begin
                symbols[2] = 5'd11; // o
                symbols[1] = 5'h1c; // F
                symbols[0] = 5'h1c; // F
            end
        end
        if (fade_mode) begin
            for (d=0; d<8; d=d+1) symbols[d] = F_BLANK;
            symbols[7] = 5'h1c; // F
            symbols[6] = 5'h1d; // A
            symbols[5] = F_D;
            symbols[4] = 5'h1a; // E
            case (fade_level)
                2'd0: symbols[0] = 5'd0;
                2'd1: symbols[0] = 5'd4;
                2'd2: symbols[0] = 5'd8;
                2'd3: begin symbols[1] = 5'd1; symbols[0] = 5'd6; end
            endcase
        end
        if (source_mode) begin
            for (d=0; d<8; d=d+1) symbols[d] = F_BLANK;
            symbols[7] = F_S;
            symbols[6] = 5'd12; // n
            symbols[5] = F_D;
            symbols[0] = source_wav ? 5'd1 : 5'd2;
        end
        if (track_mode) begin
            for (d=0; d<8; d=d+1) symbols[d] = F_BLANK;
            symbols[7] = F_P;
            symbols[6] = F_L;
            symbols[5] = 5'h1d; // A
            symbols[4] = 5'h1f; // Y
            symbols[0] = track_number == 0 ? 5'h19 : {1'b0,track_number};
        end
        if (error_code != 0) begin
            for (d=0; d<8; d=d+1) symbols[d] = F_BLANK;
            symbols[7] = 5'h1a;
            symbols[6] = F_R;
            symbols[5] = F_R;
            symbols[0] = {2'b00,error_code};
        end
    end

    // -------- scan driver --------
    reg [2:0] scan_idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= {SCAN_WIDTH{1'b0}};
            scan_idx <= 3'd0;
            dig_n    <= 8'hff;
            seg_n    <= 8'hff;
        end else if (!enable) begin
            scan_cnt <= {SCAN_WIDTH{1'b0}};
            scan_idx <= 3'd0;
            dig_n <= 8'hff;
            seg_n <= 8'hff;
        end else begin
            if (scan_cnt == SCAN_STEP_CYCLES - 1) begin
                scan_cnt <= {SCAN_WIDTH{1'b0}};
                scan_idx <= scan_idx + 1'b1;
            end else begin
                scan_cnt <= scan_cnt + 1'b1;
            end
            // Break-before-make: blank, update segments, then enable digit.
            // SCAN_STEP_CYCLES must be at least 3.
            if (scan_cnt == 0)
                dig_n <= 8'hff;
            else if (scan_cnt == 1)
                seg_n <= {1'b1, ~seg_font(symbols[scan_idx])};
            else
                dig_n <= ~(8'b0000_0001 << scan_idx);
        end
    end
endmodule
