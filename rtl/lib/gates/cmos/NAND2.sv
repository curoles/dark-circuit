/* 2-input NAND.
 *
 *
 * <script type="WaveDrom">
 * { assign:[
 *   ["out",
 *     ["~&", "in1", "in2"]
 *   ]
 * ]}
 * </script>
 * 
 * Wrapper around NAnd2
 */
module NAND2 (
    input  wire in1,
    input  wire in2,
    output wire out
);

    NAnd2 nand2_(.in1(in1), .in2(in2), .out(out));

endmodule
