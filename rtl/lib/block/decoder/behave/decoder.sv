/* Decoder SIZE to 2**SIZE, behavioral: out[in] = en, all other bits are 0.
 *
 * For example, 3 to 8 decoder: in=5 gives out=8'b0010_0000 when en=1. With en=0 the output
 * is 0 whatever in is, also an unknown in (simulation: no X out of a disabled decoder, as
 * the struct version's gates give).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Decoder #(
    parameter  SIZE  = 3,
    localparam WIDTH = 1 << SIZE
)(
    input  wire [SIZE-1:0]  in,
    input  wire             en,
    output wire [WIDTH-1:0] out
);

    assign out = en ? {{(WIDTH-1){1'b0}}, 1'b1} << in : '0;

endmodule
