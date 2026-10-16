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
 * Uses NAnd2
 */
module NAND2  #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin
        NAnd2 nand2_(.in1(in1[i]), .in2(in2[i]), .out(out[i]));
    end
    endgenerate

endmodule
