/* Complex gate And-Or-Invertor.
 *
 *
 * <pre>
 *  in1 ----------+--\
 *                AND +----+
 *  in2 ----------+--/|    |
 *                    |NOR |o-----
 *  in3 ----------+--\|    |
 *                AND +----+
 *  in4 ----------+--/
 * </pre>
 *
 * <script type="WaveDrom">
 * { assign:[
 *   ["out",
 *     ["~|",
 *       ["&", "in1", "in2"],
 *       ["&", "in3", "in4"]
 *     ]
 *   ]
 * ]}
 * </script>
 */
module AOI22 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1, // to be AND-ed with in2
    input  wire [WIDTH-1:0] in2, // to be AND-ed with in1
    input  wire [WIDTH-1:0] in3, // to be AND-ed with in4
    input  wire [WIDTH-1:0] in4, // to be AND-ed with in3
    output wire [WIDTH-1:0] out  // NOR the results of two ANDs
);

    assign out = ~((in1 & in2) | (in3 & in4));

endmodule
