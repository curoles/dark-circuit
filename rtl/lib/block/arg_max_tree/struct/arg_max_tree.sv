/* Arg max: the largest of N values that are valid, and its index; made of blocks and gates.
 *
 * Same ports and results as the behave version: the largest valid value, its index, the
 * lowest of equal ones; 0 for all three when no input is valid.
 *
 * A tree of halves: the module instantiates itself for the lower inputs (indices 0 to
 * NLO - 1, NLO the largest power of 2 below N) and the upper ones (NLO to N - 1, 1 to NLO
 * inputs), then a node picks one of the two winners:
 *
 *   values[NLO-1:0] --> ArgMaxTree u_lo --+-- lo --+
 *                                         |        +--> hi > lo? valid? --> sel_hi --> Mux2
 *   values[N-1:NLO] --> ArgMaxTree u_hi --+-- hi --+                                 --> max_*
 *
 * - hi > lo is the carry out of hi + ~lo (hi - lo - 1 does not borrow): a KoggeStoneAdder,
 *   so a node is about log2(WIDTH) gate levels and the tree log2(N) nodes deep.
 * - The upper winner is taken when it is valid and the lower one is not valid or smaller:
 *   sel_hi = hi_valid & (hi_gt | ~lo_valid). An equal value keeps the lower winner, whose
 *   indices are lower: the lowest index wins a tie.
 * - The index is {sel_hi, the winner's index}: the lower half has IW - 1 index bits, the
 *   upper half as many or fewer (extended with zeros).
 * - A leaf (N = 1) is one input: its value And-ed with its valid, index 0, so an input that
 *   is not valid counts as value 0 and every result is 0 when no input is valid.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module ArgMaxTree #(
    parameter  N     = 8,                       // inputs, 1 or more
    parameter  WIDTH = 8,                       // bits of a value
    localparam IW    = (N > 1) ? $clog2(N) : 1  // bits of an index
)(
    input  wire [N-1:0][WIDTH-1:0] values,      // values[k] counts when valid[k] is 1
    input  wire [N-1:0]            valid,
    output wire                    max_valid,   // some input is valid
    output wire [WIDTH-1:0]        max_value,   // the largest valid value, 0 if none
    output wire [IW-1:0]           max_index    // its lowest index, 0 if none
);
    `DC_STATIC_ASSERT(a_sizes, N >= 1 && WIDTH >= 1)

    // @kb: rtl/lib/block/arg_max_tree/design
    if (N == 1) begin: g_leaf
        And2 #(WIDTH) u_and2(.in1(values[0]), .in2({WIDTH{valid[0]}}), .out(max_value));
        assign max_valid = valid[0];
        assign max_index = '0;
    end else begin: g_node
        localparam NLO  = 1 << (IW - 1);                // inputs of the lower half
        localparam NHI  = N - NLO;                      // inputs of the upper half
        localparam IWLO = (NLO > 1) ? $clog2(NLO) : 1;  // their index bits
        localparam IWHI = (NHI > 1) ? $clog2(NHI) : 1;

        wire             lo_valid;
        wire             hi_valid;
        wire [WIDTH-1:0] lo_value;
        wire [WIDTH-1:0] hi_value;
        wire [WIDTH-1:0] lo_value_n;    // ~lo_value, for hi - lo - 1
        // With N = 2 the halves are single inputs: their index (0) is not used.
        /* verilator lint_off UNUSEDSIGNAL */
        wire [IWLO-1:0]  lo_index;
        wire [IWHI-1:0]  hi_index;
        wire [WIDTH-1:0] diff;          // hi - lo - 1: only its carry out is used
        /* verilator lint_on UNUSEDSIGNAL */
        wire             hi_gt;         // hi_value > lo_value
        wire             hi_gt_or_lo_n; // hi_gt | ~lo_valid
        wire             sel_hi;        // the upper half wins

        ArgMaxTree #(.N(NLO), .WIDTH(WIDTH)) u_lo(
            .values(values[NLO-1:0]), .valid(valid[NLO-1:0]),
            .max_valid(lo_valid), .max_value(lo_value), .max_index(lo_index));
        ArgMaxTree #(.N(NHI), .WIDTH(WIDTH)) u_hi(
            .values(values[N-1:NLO]), .valid(valid[N-1:NLO]),
            .max_valid(hi_valid), .max_value(hi_value), .max_index(hi_index));

        Inv #(WIDTH) u_inv(.in(lo_value), .out(lo_value_n));
        KoggeStoneAdder #(WIDTH) u_kogge_stone_adder(
            .in1(hi_value), .in2(lo_value_n), .ci(1'b0), .co(hi_gt), .sum(diff));

        Ind2 #(1) u_ind2(.in1(hi_gt), .in2(lo_valid), .out(hi_gt_or_lo_n));
        And2 #(1) u_and2(.in1(hi_valid), .in2(hi_gt_or_lo_n), .out(sel_hi));
        Or2  #(1) u_or2(.in1(lo_valid), .in2(hi_valid), .out(max_valid));
        Mux2 #(WIDTH) u_mux2_value(.in0(lo_value), .in1(hi_value), .sel(sel_hi), .out(max_value));

        if (IW == 1) begin: g_two
            assign max_index = sel_hi;
        end else begin: g_more
            wire [IW-2:0] hi_index_x;   // hi_index extended to the lower half's width
            assign hi_index_x = (IW-1)'(hi_index);
            Mux2 #(IW-1) u_mux2_index(
                .in0(lo_index), .in1(hi_index_x), .sel(sel_hi), .out(max_index[IW-2:0]));
            assign max_index[IW-1] = sel_hi;
        end
    end

endmodule
