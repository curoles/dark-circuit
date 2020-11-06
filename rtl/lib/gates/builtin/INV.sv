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
 * Wrapper around Inv.
 *
 *
 */
module INV #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out // out = ~in
);
    Inv#(WIDTH) inv_(.in(in), .out(out));
endmodule
