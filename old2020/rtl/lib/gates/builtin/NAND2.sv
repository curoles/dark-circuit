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
module NAND2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire [WIDTH-1:0] out
);

    NAnd2#(WIDTH) nand_(.in1(in1), .in2(in2), .out(out));

endmodule
