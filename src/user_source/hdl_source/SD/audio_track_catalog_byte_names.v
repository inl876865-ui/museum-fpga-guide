`timescale 1ns/1ps

// Keep up to eight short-name PCM entries in FAT directory name order.
// One comparison or move per clock avoids a wide 8-way sort path.
module audio_track_catalog_byte_names #(parameter integer ENABLE_CAPTION=0) (
    input  wire        clk,
    input  wire        rst,
    input  wire        scan_reset,
    input  wire        scan_done,
    input  wire        found_valid,
    input  wire [87:0] found_name,
    input  wire [31:0] found_cluster,
    input  wire [31:0] found_size,
    input  wire        next_event,
    input  wire        prev_event,
    output reg  [3:0]  track_count,
    output reg  [2:0]  selected_index,
    output wire [31:0] selected_cluster,
    output wire [31:0] selected_size,
    output reg         track_change,
    input wire [2:0] caption_lookup_index,
    output reg [63:0] selected_short_name,
    output wire selected_short_name_valid,
    output wire        ready
);
    localparam [2:0] COLLECT=0, LOAD_PAIR=1, COMPARE=2,
                     SWAP=3, ADVANCE=4, READY=5, READ_PAIR=6;
    reg [2:0] state;
    // Specialized scanner client: accepted input events are >=8 clocks apart.
    // Capture all 64 name bits on acceptance; abort may clear the producer.
    (* ram_style="bram" *) reg [7:0] names_left[0:63];
    (* ram_style="bram" *) reg [7:0] names_right[0:63];
    reg [7:0] name_read_left,name_read_right;
    reg name_pending;
    reg [63:0] pending_name;
    reg [2:0] pending_slot,pending_write_byte;
    (* ram_style="bram" *) reg [31:0] clusters[0:7];
    (* ram_style="bram" *) reg [31:0] sizes[0:7];
    reg [2:0] order[0:7];
    wire [7:0] left_name=name_read_left;
    wire [7:0] right_name=name_read_right;
    reg [2:0] caption_index_q,caption_index_qq;
    reg lookup_busy,completed_valid,catalog_epoch,lookup_epoch,completed_epoch;
    reg [2:0] lookup_index,lookup_slot,lookup_byte,completed_index;
    wire lookup_allowed=ENABLE_CAPTION!=0 && state==READY && !rst && !scan_reset && caption_lookup_index<track_count;
    wire completed_current=completed_valid && completed_epoch==catalog_epoch && caption_lookup_index==completed_index;
    wire lookup_stable=caption_lookup_index==caption_index_q && caption_index_q==caption_index_qq;
    assign selected_short_name_valid=lookup_allowed && completed_current && lookup_stable;
    reg [2:0] sort_position,sort_pass,byte_position;
    reg scan_went_low;
    wire [2:0] last_index=track_count[2:0]-3'd1;
    wire [2:0] last_pair=track_count[2:0]-3'd2;
    genvar slot;
    generate for(slot=0;slot<8;slot=slot+1) begin : g_order
        // Adjacent swaps need only the two fixed neighboring slots.
        always @(posedge clk or posedge rst) begin
            if(rst)order[slot]<=slot;
            else if(scan_reset)order[slot]<=slot;
            else if(state==SWAP) begin
                if(slot<7 && sort_position==slot)order[slot]<=order[(slot+1)%8];
                else if(slot>0 && sort_position==slot-1)order[slot]<=order[(slot+7)%8];
            end
        end
    end endgenerate

    wire name_write = !rst && !scan_reset && state==COLLECT &&
                      found_valid && track_count<8;
    // Predict the next comparison byte at the same edge as byte_position.
    // Each consumed sort/lookup byte was written at least one earlier edge.
    wire [2:0] sort_read_byte=(state==LOAD_PAIR || state==READ_PAIR) ? 3'd0 :
        state==COMPARE && left_name==right_name && byte_position!=7 ? byte_position+3'd1 : byte_position;
    wire [2:0] name_left_slot=ENABLE_CAPTION!=0 && state==READY ?
        (lookup_busy ? lookup_slot : order[caption_lookup_index]) : order[sort_position];
    wire [2:0] name_right_slot=order[sort_position+3'd1];
    wire [2:0] name_left_byte=ENABLE_CAPTION!=0 && state==READY ?
        (lookup_busy ? lookup_byte+3'd1 : 3'd0) : sort_read_byte;
    wire [2:0] name_right_byte=sort_read_byte;
    wire name_byte_write=!rst && !scan_reset && (name_write || name_pending);
    wire [5:0] name_write_address=name_write ? {track_count[2:0],3'd0} : {pending_slot,pending_write_byte};
    wire [7:0] name_write_data=name_write ? found_name[87:80] : pending_name[63-pending_write_byte*8 -:8];
    always @(posedge clk) begin
        if(name_byte_write) begin
            names_left[name_write_address]<=name_write_data;
            names_right[name_write_address]<=name_write_data;
        end
        name_read_left<=names_left[{name_left_slot,name_left_byte}];
        name_read_right<=names_right[{name_right_slot,name_right_byte}];
    end
    // COLLECT reads on acceptance are unused. LOAD/READ and CAP start
    // issue a fresh read before consumption, so only pending reads bypass.
    always @(posedge clk) if(name_write) pending_name<=found_name[87:24];
    always @(posedge clk or posedge rst) begin
        if(rst) begin name_pending<=0;pending_slot<=0;pending_write_byte<=0;end
        else if(scan_reset) name_pending<=0;
        else if(name_write) begin
            name_pending<=1;pending_slot<=track_count[2:0];pending_write_byte<=1;
        end else if(name_pending) begin
            if(pending_write_byte==7) name_pending<=0;
            else pending_write_byte<=pending_write_byte+3'd1;
        end
    end

    // Read the slot selected by this clock's transition, preserving same-clock
    // navigation and swap outputs while allowing metadata BRAM storage.
    wire [2:0] selected_next_index=state==READY ?
        next_event ? selected_index==last_index ? 3'd0 : selected_index+3'd1 :
        prev_event ? selected_index==0 ? last_index : selected_index-3'd1 : selected_index : 3'd0;
    // Selection remains zero until READY; only the first adjacent swap affects it.
    wire [2:0] metadata_read_address=state==SWAP && sort_position==0 ? order[1] : order[selected_next_index];
    reg [31:0] cluster_read,size_read;
    reg metadata_bypass;
    reg [31:0] cluster_bypass,size_bypass;
    // Preserve four combinational data buffers on the short metadata write paths.
    // The bypass path and every register/write/read edge remain unchanged.
    wire size_write_bit5,size_write_bit6,size_write_bit10,size_write_bit11;
    (* keep="true" *) EG_LOGIC_BUF u_size_hold_buffer5(.i(found_size[5]),.o(size_write_bit5));
    (* keep="true" *) EG_LOGIC_BUF u_size_hold_buffer10(.i(found_size[10]),.o(size_write_bit10));
    (* keep="true" *) EG_LOGIC_BUF u_size_hold_buffer6(.i(found_size[6]),.o(size_write_bit6));
    (* keep="true" *) EG_LOGIC_BUF u_size_hold_buffer11(.i(found_size[11]),.o(size_write_bit11));
    wire [31:0] size_write_data={found_size[31:12],size_write_bit11,size_write_bit10,
        found_size[9:7],size_write_bit6,size_write_bit5,found_size[4:0]};
    always @(posedge clk) begin
        if(name_write) begin
            clusters[track_count[2:0]]<=found_cluster;
            sizes[track_count[2:0]]<=size_write_data;
        end
        cluster_read<=clusters[metadata_read_address];size_read<=sizes[metadata_read_address];
        metadata_bypass<=name_write && track_count==0;
        cluster_bypass<=found_cluster;size_bypass<=found_size;
    end

    // Only the CAP observation latency changes. Completed names are qualified
    // combinationally by the current index, so the observer cannot latch stale.
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            selected_short_name<=0;caption_index_q<=0;caption_index_qq<=0;
            lookup_busy<=0;completed_valid<=0;catalog_epoch<=0;lookup_epoch<=0;completed_epoch<=0;
            lookup_index<=0;lookup_slot<=0;lookup_byte<=0;completed_index<=0;
        end else begin
            caption_index_q<=caption_lookup_index;caption_index_qq<=caption_index_q;
            if(scan_reset) begin
                catalog_epoch<=!catalog_epoch;lookup_busy<=0;completed_valid<=0;
            end else if(!lookup_allowed) begin
                lookup_busy<=0;completed_valid<=0;
            end else if(lookup_busy) begin
                if(caption_lookup_index!=lookup_index || lookup_epoch!=catalog_epoch) lookup_busy<=0;
                else begin
                    selected_short_name<={selected_short_name[55:0],left_name};
                    if(lookup_byte==7) begin
                        lookup_busy<=0;completed_valid<=1;completed_index<=lookup_index;completed_epoch<=lookup_epoch;
                    end else lookup_byte<=lookup_byte+3'd1;
                end
            end else if(!completed_current && lookup_stable) begin
                lookup_busy<=1;lookup_index<=caption_lookup_index;lookup_slot<=order[caption_lookup_index];
                lookup_epoch<=catalog_epoch;lookup_byte<=0;completed_valid<=0;
            end
        end
    end
    assign ready = state == READY;
    assign selected_cluster = track_count == 0 ? 32'd0 : metadata_bypass ? cluster_bypass : cluster_read;
    assign selected_size = track_count == 0 ? 32'd0 : metadata_bypass ? size_bypass : size_read;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= COLLECT;
            track_count <= 0;
            selected_index <= 0;
            track_change <= 0;
            sort_position <= 0;sort_pass <= 0;byte_position <= 0;
            scan_went_low <= 0;
        end else begin
            track_change <= 0;
            if (scan_reset) begin
                state <= COLLECT;
                track_count <= 0;
                selected_index <= 0;
                scan_went_low <= 0;
            end else case (state)
                COLLECT: begin
                    if(!scan_done) scan_went_low <= 1;
                    if(found_valid && track_count<8) begin
                        track_count <= track_count+1'b1;
                    end
                    if(scan_went_low && scan_done) begin
                        sort_position <= 0;
                        sort_pass <= 0;
                        state <= track_count>1 ? LOAD_PAIR : READY;
                    end
                end
                LOAD_PAIR: state <= READ_PAIR;
                READ_PAIR: begin
                    byte_position <= 0;
                    state <= COMPARE;
                end
                COMPARE: begin
                    if(left_name > right_name) state <= SWAP;
                    else if(left_name < right_name ||
                            byte_position==7) state <= ADVANCE;
                    else begin
                        byte_position <= byte_position+1'b1;
                    end
                end
                SWAP: begin
                    state <= ADVANCE;
                end
                ADVANCE: begin
                    if(sort_position==last_pair) begin
                        sort_position <= 0;
                        if(sort_pass==last_pair) state <= READY;
                        else begin sort_pass <= sort_pass+1'b1;state <= LOAD_PAIR;end
                    end else begin
                        sort_position <= sort_position+1'b1;
                        state <= LOAD_PAIR;
                    end
                end
                READY: if (track_count != 0 && next_event) begin
                    selected_index <= selected_index == last_index ?
                                      3'd0 : selected_index+1'b1;
                    track_change <= 1;
                end else if (track_count != 0 && prev_event) begin
                    selected_index <= selected_index == 0 ?
                                      last_index : selected_index-1'b1;
                    track_change <= 1;
                end
                default: state <= COLLECT;
            endcase
        end
    end
endmodule
