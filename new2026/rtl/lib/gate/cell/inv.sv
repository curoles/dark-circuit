/* Inverter.
 *
 */
module Inv #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,  // to be inverted
    output wire [WIDTH-1:0] out  // out is inverted in
);

    // TOD instead of assign out = ~in; use generate for-loop and INV cell

endmodule
