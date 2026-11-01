`timescale 1ns/1ps

module config_journal #(parameter integer SLOT_INPUTS_HELD=0) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        load_start,
    input  wire        slot0_present,
    input  wire [31:0] slot0_version,
    input  wire [31:0] slot0_period,
    input  wire [7:0]  slot0_volume,
    input  wire [7:0]  slot0_mode,
    input  wire [15:0] slot0_crc,
    input  wire        slot1_present,
    input  wire [31:0] slot1_version,
    input  wire [31:0] slot1_period,
    input  wire [7:0]  slot1_volume,
    input  wire [7:0]  slot1_mode,
    input  wire [15:0] slot1_crc,
    output reg         load_done,
    output reg         config_valid,
    output reg  [31:0] active_version,
    output reg  [31:0] active_period,
    output reg  [7:0]  active_volume,
    output reg  [7:0]  active_mode,
    output reg         active_slot,
    input  wire        save_start,
    input  wire [31:0] save_period,
    input  wire [7:0]  save_volume,
    input  wire [7:0]  save_mode,
    output reg         record_ready,
    output reg         target_slot,
    output reg  [31:0] record_version,
    output reg  [31:0] record_period,
    output reg  [7:0]  record_volume,
    output reg  [7:0]  record_mode,
    output reg  [15:0] record_crc
);
    function [15:0] crc16_chunk40;
        input [15:0] crc_in;
        input [39:0] payload;
        integer i;
        reg [15:0] crc;
        begin
            crc = crc_in;
            for (i = 39; i >= 0; i = i - 1) begin
                if (crc[15] ^ payload[i])
                    crc = {crc[14:0],1'b0} ^ 16'h1021;
                else
                    crc = {crc[14:0],1'b0};
            end
            crc16_chunk40 = crc;
        end
    endfunction

    // One byte per clock; retain the on-Flash CRC polynomial and bit order.
    function [15:0] crc16_byte;
        input [15:0] crc_in;
        input [7:0] payload;
        integer i;
        reg [15:0] crc;
        begin
            crc=crc_in;
            for(i=7;i>=0;i=i-1)
                crc={crc[14:0],1'b0} ^ ((crc[15]^payload[i]) ? 16'h1021 : 16'd0);
            crc16_byte=crc;
        end
    endfunction
    function [7:0] payload_byte;
        input [79:0] payload;
        input [3:0] index;
        begin case(index)
            0:payload_byte=payload[79:72];1:payload_byte=payload[71:64];
            2:payload_byte=payload[63:56];3:payload_byte=payload[55:48];
            4:payload_byte=payload[47:40];5:payload_byte=payload[39:32];
            6:payload_byte=payload[31:24];7:payload_byte=payload[23:16];
            8:payload_byte=payload[15:8];default:payload_byte=payload[7:0];
        endcase end
    endfunction

    function version_newer;
        input [31:0] candidate;
        input [31:0] reference;
        reg [31:0] delta;
        begin
            delta = candidate - reference;
            version_newer = (candidate != reference) && !delta[31];
        end
    endfunction

    reg [1:0] load_phase;
    reg save_pending;
    reg [3:0] load_byte_index,save_byte_index;
    wire slot0_present_q;
    wire slot1_present_q;
    wire [31:0] slot0_version_q;
    wire [31:0] slot1_version_q;
    wire [31:0] slot0_period_q;
    wire [31:0] slot1_period_q;
    wire [7:0] slot0_volume_q;
    wire [7:0] slot1_volume_q;
    wire [7:0] slot0_mode_q;
    wire [7:0] slot1_mode_q;
    wire [15:0] slot0_crc_q;
    wire [15:0] slot1_crc_q;
    // The enclosing Flash journal owns and holds both slot records through
    // load_done. Independent users keep the accepted-load snapshot by default.
    wire [193:0] slot_inputs={slot0_present,slot1_present,
        slot0_version,slot1_version,slot0_period,slot1_period,
        slot0_volume,slot1_volume,slot0_mode,slot1_mode,slot0_crc,slot1_crc};
    wire [193:0] slot_snapshot;
    assign {slot0_present_q,slot1_present_q,slot0_version_q,slot1_version_q,
        slot0_period_q,slot1_period_q,slot0_volume_q,slot1_volume_q,
        slot0_mode_q,slot1_mode_q,slot0_crc_q,slot1_crc_q}=slot_snapshot;
    generate if(SLOT_INPUTS_HELD!=0) begin:g_held_slots
        // The caller holds every slot field through load_done. Locally capture
        // only the two presence flags, cutting their long selection fanout;
        // all other fields keep the existing held-record path and timing.
        reg [1:0] held_presence;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) held_presence<=0;
            else if(load_start) held_presence<=slot_inputs[193:192];
        end
        assign slot_snapshot={held_presence,slot_inputs[191:0]};
    end else begin:g_slot_snapshot
        reg [193:0] accepted_slots;
        assign slot_snapshot=accepted_slots;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) accepted_slots<=194'd0;
            else if(load_start) accepted_slots<=slot_inputs;
        end
    end endgenerate

    reg [15:0] slot0_crc_mid;
    reg [15:0] slot1_crc_mid;
    wire [15:0] slot0_crc_calc=slot0_crc_mid;
    wire [15:0] slot1_crc_calc=slot1_crc_mid;
    reg [15:0] save_crc_mid;
    reg slot1_newer_q;
    reg [1:0] selected_slot;

    // The first four CRC bytes are also the version, most significant first.
    // Compare the low 31 bits in that order; the top-bit XOR plus unsigned
    // borrow exactly reproduces the sign of the original modular subtraction.
    reg version_prefix_equal,version_prefix_less;
    wire [7:0] slot0_load_byte=payload_byte({slot0_version_q,slot0_period_q,slot0_volume_q,slot0_mode_q},load_byte_index);
    wire [7:0] slot1_load_byte=payload_byte({slot1_version_q,slot1_period_q,slot1_volume_q,slot1_mode_q},load_byte_index);
    wire [7:0] version0_byte=load_byte_index==0 ? {1'b0,slot0_load_byte[6:0]} : slot0_load_byte;
    wire [7:0] version1_byte=load_byte_index==0 ? {1'b0,slot1_load_byte[6:0]} : slot1_load_byte;
    wire version_equal_next=(load_byte_index==0 || version_prefix_equal) && version1_byte==version0_byte;
    wire version_less_next=(load_byte_index==0 || version_prefix_equal) ? version1_byte<version0_byte : version_prefix_less;
    wire version_sign_xor=slot1_version_q[31]^slot0_version_q[31];

    wire slot0_good = slot0_present_q && slot0_crc_q == slot0_crc_calc;
    wire slot1_good = slot1_present_q && slot1_crc_q == slot1_crc_calc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_done<=0; config_valid<=0; active_version<=0; active_period<=0;
            active_volume<=0; active_mode<=0; active_slot<=0;
            record_ready<=0; target_slot<=0;
            record_version<=0; record_period<=0; record_volume<=0; record_mode<=0;
            record_crc<=0;
            load_phase<=0; save_pending<=0;
            load_byte_index<=0;save_byte_index<=0;
             
             
             
             
             
             
            slot0_crc_mid<=0; slot1_crc_mid<=0;
            save_crc_mid<=0;
            slot1_newer_q<=0; selected_slot<=0;version_prefix_equal<=0;version_prefix_less<=0;
        end else begin
            load_done<=0;
            record_ready<=0;
            if(load_start) begin
                load_phase<=1;load_byte_index<=0;
                
                
                
                
                
                
                
                
                
                
                
                
                slot0_crc_mid<=16'hffff;
                slot1_crc_mid<=16'hffff;
            end else if(load_phase==1) begin
                slot0_crc_mid<=crc16_byte(slot0_crc_mid,slot0_load_byte);
                slot1_crc_mid<=crc16_byte(slot1_crc_mid,slot1_load_byte);
                if(load_byte_index==9) begin
                    load_phase<=2;


                end else load_byte_index<=load_byte_index+1'b1;
                if(load_byte_index<4) begin
                    version_prefix_equal<=version_equal_next;
                    version_prefix_less<=version_less_next;
                    if(load_byte_index==3)
                        slot1_newer_q<=(version_sign_xor || !version_equal_next) && !(version_sign_xor^version_less_next);
                end
            end else if(load_phase==2) begin
                load_phase<=3;
                if(slot0_good && (!slot1_good || !slot1_newer_q))
                    selected_slot<=1;
                else if(slot1_good)
                    selected_slot<=2;
                else
                    selected_slot<=0;
            end else if(load_phase==3) begin
                load_phase<=0;
                load_done<=1;
                if(selected_slot==1) begin
                    config_valid<=1; active_version<=slot0_version_q; active_period<=slot0_period_q;
                    active_volume<=slot0_volume_q; active_mode<=slot0_mode_q; active_slot<=1'b0;
                end else if(selected_slot==2) begin
                    config_valid<=1; active_version<=slot1_version_q; active_period<=slot1_period_q;
                    active_volume<=slot1_volume_q; active_mode<=slot1_mode_q; active_slot<=1'b1;
                end else begin
                    config_valid<=0; active_version<=0; active_period<=0;
                    active_volume<=0; active_mode<=0; active_slot<=1'b0;
                end
            end
            if(save_start) begin
                target_slot <= config_valid ? ~active_slot : 1'b0;
                record_version <= active_version + 1'b1;
                record_period <= save_period;
                record_volume <= save_volume;
                record_mode <= save_mode;
                save_crc_mid <= 16'hffff;save_byte_index<=0;
                save_pending <= 1'b1;
            end else if(save_pending) begin
                save_crc_mid<=crc16_byte(save_crc_mid,payload_byte(
                    {record_version,record_period,record_volume,record_mode},save_byte_index));
                if(save_byte_index==9) begin
                    save_pending <= 1'b0;
                    record_crc<=crc16_byte(save_crc_mid,payload_byte(
                        {record_version,record_period,record_volume,record_mode},save_byte_index));
                    record_ready <= 1'b1;
                end else save_byte_index<=save_byte_index+1'b1;
            end
        end
    end
endmodule
