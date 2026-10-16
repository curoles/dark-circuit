/* Multiplexer made with NAND
 *
 * Author: Igor Lesik 2020.
 *
 * <script type="WaveDrom">
 * { assign:[
 *   ["out",
 *     ["~&",
 *       ["~&", "in1", "sel"],
 *       ["~&", "in2", "~sel"]
 *     ]
 *   ]
 * ]}
 * </script>
 *
 * <pre> 
 *                  +------+
 *                  |      |
 *  in1 +-----------+ NAND |
 *                  |      |o+-+    +------+
 *  sel +-----+-----+      |   |    |      |
 *            |     |      |   |    |      |
 *            |     +------+   +----+ NAND |
 *            |                     |      |o+----+ out
 *            |     +------+   +----+      |
 *            |     |      |   |    |      |
 *            +---+o| NAND |   |    |      |
 *                  |      |o+-+    +------+
 *  in2 +-----------+      |
 *                  |      |
 *                  +------+
 *  </pre>
 */
module Mux2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire              sel,
    output wire [WIDTH-1:0]  out
);

    wire [WIDTH-1:0] o1, o2;
    NAND2#(WIDTH) nand1_(.out(o1), .in1(in1), .in2({WIDTH{sel}}));
    NAND2#(WIDTH) nand2_(.out(o2), .in1(in2), .in2({WIDTH{~sel}}));
    NAND2#(WIDTH) nand3_(.out(out), .in1(o1), .in2(o2));

endmodule
