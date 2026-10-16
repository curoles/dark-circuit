/* 2-input AND.
 *
 *
 * <script type="WaveDrom">
 * { assign:[
 *   ["out",
 *     ["&", "in1", "in2"]
 *   ]
 * ]}
 * </script>
 * 
 */
module AND2 (
    input  wire in1,
    input  wire in2,
    output wire out
);
    wire nand_output;
    NAnd2 nand2_(.in1(in1), .in2(in2), .out(nand_output));
    Inv   inv_  (.in(nand_output), .out(out));

endmodule
