/* Priority encoder 2**SIZE to SIZE, made of gates:
 * out is index of the highest bit set in in, valid is 1 if any bit of in is set;
 * out and valid are 0 when in is 0.
 *
 * A tree of halves, by recursion: each half is a PriorityEncoder of SIZE - 1. The upper half
 * wins when one of its bits is set (hi_valid): out's top bit is hi_valid, its other bits the
 * upper half's out or else the lower half's (a Mux2), valid the OR of both valids. A leaf
 * (SIZE 1, 2 bits) is out = in[1], valid = in[1] | in[0]. Depth: SIZE levels of an Or2 and a
 * Mux2 (about 10 gate levels for 32 bits), not the WIDTH - 1 Or2 of a chain from the top;
 * every node is its own instance, so there are no arrays of levels (Verilator saw a false
 * loop in them, kb rtl/lib/block/priority_encoder/dropped_tree).
 *
 *   in[WIDTH-1:HALF] --> PriorityEncoder SIZE-1 --> hi_out, hi_valid --+--> out[SIZE-1]
 *                                                        |              |
 *   in[HALF-1:0] -----> PriorityEncoder SIZE-1 --> lo_out --> Mux2 -----+--> out[SIZE-2:0]
 *                                                  lo_valid --> Or2 (hi_valid) --> valid
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module PriorityEncoder #(
    parameter  SIZE  = 3,
    localparam WIDTH = 1 << SIZE
)(
    input  wire [WIDTH-1:0] in,
    output wire [SIZE-1:0]  out,   // index of the highest bit set in in, 0 if none
    output wire             valid  // 1 if any bit of in is set
);
    `DC_STATIC_ASSERT(a_size, SIZE >= 1)

    // @kb: rtl/lib/block/priority_encoder/tree
    if (SIZE == 1) begin: g_leaf
        assign out = in[1];
        Or2 #(1) u_or2_valid(.in1(in[1]), .in2(in[0]), .out(valid));
    end else begin: g_node
        localparam HALF = WIDTH / 2;

        wire [SIZE-2:0] lo_out;     // index in the lower half
        wire [SIZE-2:0] hi_out;     // index in the upper half
        wire            lo_valid;   // a bit of the lower half is set
        wire            hi_valid;   // a bit of the upper half is set: it wins

        PriorityEncoder #(.SIZE(SIZE - 1)) u_lo(
            .in(in[HALF-1:0]), .out(lo_out), .valid(lo_valid));
        PriorityEncoder #(.SIZE(SIZE - 1)) u_hi(
            .in(in[WIDTH-1:HALF]), .out(hi_out), .valid(hi_valid));

        Mux2 #(SIZE - 1) u_mux2_out(
            .in0(lo_out), .in1(hi_out), .sel(hi_valid), .out(out[SIZE-2:0]));
        assign out[SIZE-1] = hi_valid;
        Or2 #(1) u_or2_valid(.in1(lo_valid), .in2(hi_valid), .out(valid));
    end

endmodule
