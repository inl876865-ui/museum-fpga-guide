`timescale 1ns/1ps

// Keep up to eight short-name PCM entries in FAT directory name order.
// One comparison or move per clock avoids a wide 8-way sort path.
module audio_track_catalog #(parameter integer ENABLE_CAPTION=0) (
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
    output reg selected_short_name_valid,
    output wire        ready
);
    localparam [2:0] COLLECT=0, LOAD_PAIR=1, COMPARE=2,
                     SWAP=3, ADVANCE=4, READY=5, READ_PAIR=6;
    reg [2:0] state;
    // Every accepted extension is PCM, so its equal three bytes need no storage.
    (* ram_style="bram" *) reg [63:0] names [0:7];
    reg [63:0] name_read_left,name_read_right;
    (* ram_style="bram" *) reg [31:0] clusters [0:7];
    (* ram_style="bram" *) reg [31:0] sizes [0:7];
    // Sort three-bit indices; file metadata stays in its collected slot.
    reg [2:0] order [0:7];
    // RAM read outputs stay fixed from READ_PAIR through COMPARE.
    // Select a byte directly; comparison/state latency remains unchanged.
    wire [7:0] left_name=name_read_left[63-byte_position[2:0]*8 -: 8];
    wire [7:0] right_name=name_read_right[63-byte_position[2:0]*8 -: 8];
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
    wire [2:0] name_left_address = state==COLLECT ? track_count[2:0] :
                                   (ENABLE_CAPTION!=0 && state==READY ? order[caption_lookup_index] : order[sort_position[2:0]]);
    wire [2:0] name_right_address = order[sort_position[2:0]+3'd1];
    // Two synchronous RAM ports; validity comes from track_count, not RAM reset.
    always @(posedge clk) begin
        if(name_write) names[name_left_address] <= found_name[87:24];
        name_read_left <= names[name_left_address];
    end
    always @(posedge clk) name_read_right <= names[name_right_address];

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
    always @(posedge clk) begin
        if(name_write) begin
            clusters[track_count[2:0]]<=found_cluster;
            sizes[track_count[2:0]]<=found_size;
        end
        cluster_read<=clusters[metadata_read_address];size_read<=sizes[metadata_read_address];
        metadata_bypass<=name_write && track_count==0;
        cluster_bypass<=found_cluster;size_bypass<=found_size;
    end

    reg [2:0] caption_index_q,caption_index_qq;
    always @(posedge clk or posedge rst) begin
        if(rst) begin selected_short_name<=0;selected_short_name_valid<=0;caption_index_q<=0;caption_index_qq<=0;end
        else begin
            caption_index_q<=caption_lookup_index;caption_index_qq<=caption_index_q;
            selected_short_name<=name_read_left;
            selected_short_name_valid<=ENABLE_CAPTION!=0 && state==READY && !scan_reset &&
                caption_lookup_index<track_count && caption_lookup_index==caption_index_q && caption_index_q==caption_index_qq;
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
