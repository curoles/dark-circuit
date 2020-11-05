/* Complex gate OR-AND-Invertor.
 *
 *
 * <pre>
 *  in1 ----------+--\
 *                )OR +----+
 *  in2 ----------+--/|    |
 *                    |NAND|o-----
 *  in3 ----------+--\|    |
 *                )OR +----+
 *  in4 ----------+--/
 * </pre>
 *
 * <script type="WaveDrom">
 * { assign:[
 *   ["out",
 *     ["~&",
 *       ["|", "in1", "in2"],
 *       ["|", "in3", "in4"]
 *     ]
 *   ]
 * ]}
 * </script>
 */
module OAI22 #(
    parameter WIDTH = 8 // number of 1-bit gates
)(
    input  wire [WIDTH-1:0] in1, // to be OR-ed with in2
    input  wire [WIDTH-1:0] in2, // to be OR-ed with in1
    input  wire [WIDTH-1:0] in3, // to be OR-ed with in4
    input  wire [WIDTH-1:0] in4, // to be OR-ed with in3
    output wire [WIDTH-1:0] out  // NAND the results of two ORs
);

    assign out = ~((in1 | in2) & (in3 | in4));

endmodule
