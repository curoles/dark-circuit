/* 2-input NOR
 *
 *
 * <script type="WaveDrom">
 * { assign:[
 *   ["out",
 *     ["~|", "in1", "in2"]
 *   ]
 * ]}
 * </script>
 *
 * Wrapper around NOr2 
 */

module NOR2 (
    input  wire in1,
    input  wire in2,
    output wire out
);

    NOr2 nor2_(.in1(in1), .in2(in2), .out(out));

endmodule
