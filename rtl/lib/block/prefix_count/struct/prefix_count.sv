/* Prefix count: for every bit of in, the number of ones below it; made of parts.
 *
 * Same ports and counts as the behave version. A parallel prefix, as the carries of
 * KoggeStoneAdder: at level 0 every bit is a count of itself (0 or 1); level l adds to every
 * count the one 2^l below it, so after level l the count at bit k covers bits k down to
 * k - 2^(l+1) + 1. After the last level, run[k] is the number of ones in in[k:0]; prefix[k]
 * is run[k-1] and total is run[WIDTH-1].
 *
 *   level 0:  run = in, one bit per count
 *   level l:  run[k] += run[k - 2^l]     (k >= 2^l; the others keep their count)
 *   prefix[k] = run[k-1], prefix[0] = 0, total = run[WIDTH-1]
 *
 * A count before level l covers at most 2^l bits, so it has l + 1 bits, and the sum
 * l + 2: every adder is a KoggeStoneAdder of l + 1 bits whose carry out is the sum's top
 * bit (of CW bits at most: a count never exceeds WIDTH). The bits above are 0, constants
 * that synthesis removes. log2(WIDTH) levels of small adders, about WIDTH of them a level.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module PrefixCount #(
    parameter  WIDTH = 32,
    localparam CW    = $clog2(WIDTH + 1)        // bits of a count 0..WIDTH
)(
    input  wire [WIDTH-1:0]         in,
    output wire [WIDTH-1:0][CW-1:0] prefix,     // prefix[k]: ones in in[k-1:0]
    output wire [CW-1:0]            total       // ones in in
);
    `DC_STATIC_ASSERT(a_width, WIDTH >= 1)

    localparam LEVELS = $clog2(WIDTH);

    // run[l][k]: the ones in in[k:k-2^l+1] (down to bit 0 when lower), before level l.
    // split_var: Verilator treats the levels separately, no false loop.
    wire [WIDTH-1:0][CW-1:0] run [0:LEVELS] /*verilator split_var*/;

    for (genvar k = 0; k < WIDTH; k++) begin : g_bit
        assign run[0][k] = CW'(in[k]);
    end

    // @kb: rtl/lib/block/prefix_count/design
    for (genvar l = 0; l < LEVELS; l++) begin : g_level
        localparam S  = 1 << l;                         // distance of the added count
        localparam B  = (l + 1 < CW) ? l + 1 : CW;      // bits of a count before level l
        for (genvar k = 0; k < WIDTH; k++) begin : g_bit
            if (k < S) begin : g_keep
                assign run[l+1][k] = run[l][k];
            end else if (B < CW) begin : g_add_wide
                // The carry out is the sum's top bit.
                KoggeStoneAdder #(B) u_kogge_stone_adder(
                    .in1(run[l][k][B-1:0]), .in2(run[l][k-S][B-1:0]), .ci(1'b0),
                    .co(run[l+1][k][B]), .sum(run[l+1][k][B-1:0]));
                if (B + 1 < CW) begin : g_zero
                    assign run[l+1][k][CW-1:B+1] = '0;
                end
            end else begin : g_add
                // The count fits in CW bits: no carry out.
                /* verilator lint_off UNUSEDSIGNAL */
                wire co;
                /* verilator lint_on UNUSEDSIGNAL */
                KoggeStoneAdder #(CW) u_kogge_stone_adder(
                    .in1(run[l][k]), .in2(run[l][k-S]), .ci(1'b0), .co,
                    .sum(run[l+1][k]));
            end
        end
    end

    assign prefix[0] = '0;
    if (WIDTH > 1) begin : g_prefix
        assign prefix[WIDTH-1:1] = run[LEVELS][WIDTH-2:0];
    end
    assign total = run[LEVELS][WIDTH-1];

endmodule
