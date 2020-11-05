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
 */

module NAnd2 (
    input  wire in1,
    input  wire in2,
    output wire out
);

    nand /*(strength)*/ /*#(3 delays)*/ nand_(out, in1, in2);

endmodule
