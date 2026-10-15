/* 2:1 Multiplexer.
 *
 * Author: Igor Lesik 2014.
 *
 * <pre>
 *           +-----+
 * in1 ------| 1   |
 *           | MUX |--- out
 * in0 ------| 0   |
 *           +--+--+
 *         sel  |
 * </pre>
 */
module Mux2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in0,  // selected when sel is 0
    input  wire [WIDTH-1:0]  in1,  // selected when sel is 1
    input  wire              sel,
    output wire [WIDTH-1:0]  out
);

    assign out = sel ? in1 : in0;

endmodule
