/* Arg max: the largest of N values that are valid, and its index; purely combinational.
 *
 * max_valid is 1 when some input is valid. max_value is the largest valid value, max_index
 * its index; when several valid inputs have that value, the lowest index (the rule of the
 * RISC-V PLIC for interrupt priorities: the lowest ID wins a tie). With no valid input
 * max_valid, max_value and max_index are 0. Values are unsigned. N is 1 or more, not only a
 * power of 2; an index has IW bits (1 when N is 1).
 *
 * For example, N = 4, WIDTH = 3:
 *   values 5 7 7 2, valid 1 1 1 1:  max_value 7, max_index 1 (1 and 2 tie: the lower)
 *   values 5 7 7 2, valid 1 0 0 1:  max_value 5, max_index 0
 *   valid 0 0 0 0:                  max_valid 0, max_value 0, max_index 0
 *
 * Uses: the highest-priority pending interrupt of a PLIC target, a priority arbiter, a
 * scheduler, the top-1 of a row of scores.
 *
 * The behave version scans the inputs from index 0 up and keeps an input only when it is
 * larger than the one kept: an equal one later does not replace it. The struct version is a
 * tree of halves.
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

    // {valid, value, index} of the largest valid input, the lowest index of equal ones.
    function automatic [IW+WIDTH:0] arg_max(input [N-1:0][WIDTH-1:0] v, input [N-1:0] vld);
        logic             found;
        logic [WIDTH-1:0] best;
        logic [IW-1:0]    idx;
        found = 1'b0;
        best  = '0;
        idx   = '0;
        for (int k = 0; k < N; k++)
            if (vld[k] && (!found || v[k] > best)) begin
                found = 1'b1;
                best  = v[k];
                idx   = IW'(k);
            end
        return {found, best, idx};
    endfunction

    assign {max_valid, max_value, max_index} = arg_max(values, valid);

endmodule
