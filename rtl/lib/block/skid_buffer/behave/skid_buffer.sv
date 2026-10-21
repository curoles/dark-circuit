/* Skid buffer: valid/ready register stage, behavioral.
 *
 * Items from channel in come out of channel out one cycle later, one item per cycle at
 * full speed. out_valid and out_data come from the output register, in_ready from the
 * skid register: all outputs are flip-flops, so the buffer cuts combinational paths in
 * both directions (valid/ready rules in AGENTS.md). When out stalls (out_valid=1,
 * out_ready=0) an item that arrives in the same cycle goes into the skid register and
 * in_ready becomes 0; the skid item moves to the output register when out takes the
 * waiting one. rst_n=0 empties both registers; data registers are not reset.
 */
module SkidBuffer #(
    parameter DATA_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,       // synchronous reset, active low: empty

    input  wire                  in_valid,    // channel in
    output wire                  in_ready,
    input  wire [DATA_WIDTH-1:0] in_data,

    output reg                   out_valid,   // channel out
    input  wire                  out_ready,
    output reg  [DATA_WIDTH-1:0] out_data
);
    reg                  skid_valid;          // the skid register holds an item
    reg [DATA_WIDTH-1:0] skid_data;
    wire                 stall;               // out holds an item that is not taken
    wire                 any;                 // an item is waiting: in the skid register or at in

    assign in_ready = !skid_valid;
    assign stall    = out_valid && !out_ready;
    assign any      = skid_valid || in_valid;

    always_ff @(posedge clk)
        if (!rst_n) begin
            out_valid  <= 1'b0;
            skid_valid <= 1'b0;
        end else begin
            out_valid  <= stall || any;       // stall: keep the item; else take the next one
            skid_valid <= stall && any;       // out stalls and an item waits: it skids
        end

    // The next item for out is the skid item when there is one (it is older), else in.
    // The skid register loads in_data while empty: nobody reads it until skid_valid=1.
    always_ff @(posedge clk) begin
        if (!stall)      out_data  <= skid_valid ? skid_data : in_data;
        if (!skid_valid) skid_data <= in_data;
    end

endmodule
