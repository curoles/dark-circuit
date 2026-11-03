/* Flow-through buffer: a valid/ready stage of one entry that cuts the ready path only,
 * behavioral.
 *
 * in_ready is "the entry is empty", a flip-flop: the sender never sees the receiver's ready
 * through this stage. Valid and data still pass forward without a flop: while the entry is
 * empty, an item at in is offered at out in the same clock (it flows through) and, when out
 * takes it, it is gone at that edge; when out does not take it, it stays in the entry and is
 * offered from there until out takes it. While the entry holds an item nothing is taken
 * (in_ready=0), also in the clock out takes the held item: taking one then would make
 * in_ready follow out_ready again. So after it held an item the buffer takes the next one a
 * clock later; without stalls it moves one item per clock with no added clock. The pattern:
 * kb record rtl/lib/block/flow_through_buffer/design (Chisel's Queue(1, flow = true));
 * SkidBuffer cuts both directions with a clock more. rst_n=0 empties the entry; its data
 * register is not reset.
 *
 *   in_valid -------------------------------> OR ---------------------------> out_valid
 *                                    full --^
 *   in_data --+-----------------------> in0 +-----+
 *             |    +-------+                | MUX |---------------------> out_data
 *             +--->| entry |----------> in1 +-----+
 *    load while    +-------+                   ^ sel: full
 *    empty
 *   full     <= out_valid AND NOT out_ready     (an item offered and not taken stays)
 *   in_ready  = NOT full                        (a flip-flop: out_ready does not reach it)
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module FlowThroughBuffer #(
    parameter DATA_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,       // synchronous reset, active low: empty

    input  wire                  in_valid,    // channel in
    output wire                  in_ready,    // the entry is empty: a flip-flop
    input  wire [DATA_WIDTH-1:0] in_data,

    output wire                  out_valid,   // channel out
    input  wire                  out_ready,
    output wire [DATA_WIDTH-1:0] out_data
);
    logic                  full;              // the entry holds an item out did not take
    logic [DATA_WIDTH-1:0] entry;

    // @kb: rtl/lib/block/flow_through_buffer/design
    assign in_ready  = !full;
    assign out_valid = full || in_valid;
    assign out_data  = full ? entry : in_data;

    // An item offered at out and not taken is in the entry after the edge: the one that
    // flowed through (empty) or the one already held (full).
    always_ff @(posedge clk)
        if (!rst_n) full <= 1'b0;
        else        full <= out_valid && !out_ready;

    // The entry loads in_data while empty: nobody reads it until full=1.
    always_ff @(posedge clk)
        if (!full)
            entry <= in_data;

endmodule
