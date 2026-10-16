/* 2-input NAND with 1 inverted input.
 *
 *
 * <script type="WaveDrom">
 * { assign:[
 *   ["out",
 *     ["~&", "~in1", "in2"]
 *   ]
 * ]}
 * </script>
 * 
 */
module IND2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire [WIDTH-1:0] out
);

    assign out = ~(~in1 & in2);

endmodule
