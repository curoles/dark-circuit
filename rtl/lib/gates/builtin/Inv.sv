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
module Inv(
    input wire in,
    output wire out // out = ~in
);
    not /*(strength)*/ /*#(2 delays)*/ not_(out, in);

endmodule
