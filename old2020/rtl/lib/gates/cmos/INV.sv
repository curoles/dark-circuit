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
 * Uses Inv.
 *
 */
module INV #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out // out = ~in
);
    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin
        Inv inv_(.in(in[i]), .out(out[i]));
    end
    endgenerate

endmodule
