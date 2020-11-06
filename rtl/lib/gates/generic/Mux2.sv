/* 2-input Multiplexer.
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
 */
module Mux2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire              sel,
    output wire [WIDTH-1:0]  out
);

    assign out = (sel == 0) ? in1 : in2;

endmodule
