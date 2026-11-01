`timescale 1ns/1ps

// Four application clients share the shipped SDRAM controller. Grants remain
// stable through every read return and the physical write-recovery tail.
module media_memory_arbiter (
    input wire clk,rst,initialized,controller_busy,refresh_busy,
    input wire [3:0] request,busy,
    output reg [3:0] grant
);
    reg [1:0] idle_history;
    reg transaction_seen;
    wire drained=&idle_history;
    wire selected_busy=|(busy & grant);
    wire selected_request=|(request & grant);
    always @(posedge clk or posedge rst) begin
        if(rst) begin idle_history<=0;grant<=0;transaction_seen<=0;end
        else begin
            idle_history<={idle_history[0],!controller_busy && !refresh_busy};
            if(grant==0) begin
                transaction_seen<=0;
                if(initialized && drained) begin
                    // Display first, then full-frame writes, then sampled writes.
                    if(request[0]) grant<=4'b0001;
                    else if(request[3]) grant<=4'b1000;
                    else if(request[1]) grant<=4'b0010;
                    else if(request[2]) grant<=4'b0100;
                end
            end else begin
                if(selected_busy) transaction_seen<=1;
                if(!selected_busy && drained && (transaction_seen || !selected_request)) begin
                    grant<=0;transaction_seen<=0;
                end
            end
        end
    end
endmodule
