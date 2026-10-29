/* Population count: count = number of ones in in, made of blocks and parts.
 *
 * Same ports and count as the behave version. Every bit of in is a row of CW bits (the bit,
 * then zeros); a WallaceTree adds the WIDTH rows down to two, a KoggeStoneAdder adds those.
 * The upper bits of the rows are constant 0, so synthesis removes most of the tree's full
 * adders: what is left is a tree of counters, each column only as wide as its sum can get.
 * WIDTH is 1 or more, not only a power of 2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module PopCount #(
    parameter  WIDTH = 32,
    localparam CW    = $clog2(WIDTH + 1)    // bits of a count 0..WIDTH
)(
    input  wire [WIDTH-1:0] in,
    output wire [CW-1:0]    count           // number of ones in in
);
    wire [CW-1:0] rows [WIDTH];     // row k: in[k] as a number of CW bits
    wire [CW-1:0] sum;              // the tree's two rows
    wire [CW-1:0] carry;
    // The count fits in CW bits: no carry out.
    /* verilator lint_off UNUSEDSIGNAL */
    wire          co;
    /* verilator lint_on UNUSEDSIGNAL */

    for (genvar k = 0; k < WIDTH; k++) begin : g_row
        assign rows[k] = CW'(in[k]);
    end

    // @kb: rtl/lib/block/compute_core_bitmanip/library_block
    WallaceTree #(.ROWS(WIDTH), .WIDTH(CW)) u_wallace_tree(.rows, .sum, .carry);
    KoggeStoneAdder #(CW) u_kogge_stone_adder(
        .in1(sum), .in2(carry), .ci(1'b0), .co, .sum(count));

endmodule
