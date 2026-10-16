/* 2:1 Multiplexer.
 * 
 * Author: Igor Lesik 2014.
 *
 * <!--script type="WaveDrom">
 * { assign:[
 *   ["out",
 *     ["?", "sel", "in1", "in2"]
 *   ]
 * ]}
 * </script-->
 *
 * <pre>
 *           +-----+
 * in1 ------| 1   |
 *           | MUX |--- out   
 * in2 ------| 0   |
 *           +--+--+
 *         sel  |
 * </pre>
 */
module Mux2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire              sel,
    output wire [WIDTH-1:0]  out
);

    assign out = (sel == 1) ? in1 : in2;

endmodule
