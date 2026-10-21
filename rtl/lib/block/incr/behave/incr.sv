/* Incrementer, behavioral.
 *
 * out = in + 1, co is carry out: 1 when in is all ones (out wraps to 0).
 *
 * @author    Igor Lesik
 * @copyright 2019 Igor Lesik, MIT License
 */
module Incr #(
    parameter WIDTH = 16,
    // Not used here, it shapes the struct version; kept so both versions have the same parameters.
    /* verilator lint_off UNUSEDPARAM */
    parameter GROUP = 4      // bits in group, the last group may be shorter
    /* verilator lint_on UNUSEDPARAM */
)(
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out,  // in + 1
    output wire             co    // carry out: in was all ones
);

    assign {co, out} = in + 1'b1;

endmodule
