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
module INV #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,  // to be inverted
    output wire [WIDTH-1:0] out  // out is inverted in
);

    assign out = ~in;

endmodule
