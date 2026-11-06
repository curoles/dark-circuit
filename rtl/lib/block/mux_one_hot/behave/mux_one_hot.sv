/* Multiplexer of N inputs by a one-hot select, behavioral: out = in[k] when sel[k] is the
 * only 1.
 *
 * The inputs are one packed array, input k in in[k], as MuxN's. sel has one bit per input,
 * as a decoder of addresses or the hits of a cache's ways give it: no encoding to a binary
 * select. out is the OR of the inputs whose select is 1, so 0 when none is (a reserved
 * address reads 0) and defined when several are (their OR). The gates are an AND per input
 * and an OR of them per bit, as a RegFile read port.
 *
 *   in[0]   -- AND sel[0]   --+
 *   in[1]   -- AND sel[1]   --+-- OR --> out
 *   ...                       |
 *   in[N-1] -- AND sel[N-1] --+
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module MuxOneHot #(
    parameter N     = 4,                    // inputs
    parameter WIDTH = 1                     // bits of an input
)(
    input  wire [N-1:0][WIDTH-1:0] in,      // input k: in[k]
    input  wire [N-1:0]            sel,     // sel[k]: input k is selected
    output wire [WIDTH-1:0]        out
);
    `DC_STATIC_ASSERT(a_inputs, N >= 1 && WIDTH >= 1)

    // The OR of the selected inputs.
    function automatic logic [WIDTH-1:0] selected(input logic [N-1:0][WIDTH-1:0] i,
                                                  input logic [N-1:0] s);
        logic [WIDTH-1:0] o;
        o = '0;
        for (int k = 0; k < N; k++)
            if (s[k])
                o = o | i[k];
        return o;
    endfunction

    // @kb: rtl/lib/block/mux_one_hot/design
    assign out = selected(in, sel);

endmodule
