/* Inverter.
 *
 * <script type="WaveDrom">
 * { assign:[
 *   ["out",
 *     ["~", "in"]
 *   ]
 * ]}
 * </script>
 *
 */
module Inv #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out // out = ~in
);
    not /*(strength)*/ /*#(2 delays)*/ not_(out, in);

endmodule
