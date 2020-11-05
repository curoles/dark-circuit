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
module INV(
    input wire in,
    output wire out // out = ~in
);
    Inv inv_(.in(in), .out(out));
endmodule
