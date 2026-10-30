/* Multiplexer of N inputs, behavioral: out = in[sel].
 *
 * The inputs are one packed array, input k in in[k]; a caller can also pass the
 * concatenation {in_N-1, ..., in_1, in_0}. sel is binary, $clog2(N) bits. sel >= N (N not
 * a power of 2) is not allowed and out is undefined then: the struct version leaves out the
 * gates such a sel would need. A caller that may present such a sel while it uses out
 * asserts against it there (MuxN has no clock).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module MuxN #(
    parameter  N         = 4,               // inputs, at least 2
    parameter  WIDTH     = 1,               // bits of an input
    localparam SEL_WIDTH = $clog2(N)
)(
    input  wire [N-1:0][WIDTH-1:0] in,      // input k: in[k]
    input  wire [SEL_WIDTH-1:0]    sel,     // below N
    output wire [WIDTH-1:0]        out
);
    `DC_STATIC_ASSERT(a_two_inputs, N >= 2)

    // @kb: rtl/lib/block/mux_n/design
    assign out = in[sel];

endmodule
