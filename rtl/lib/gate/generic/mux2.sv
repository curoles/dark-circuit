/* 2:1 Multiplexer.
 *
 * <pre>
 *           +-----+
 * in1 ------| 1   |
 *           | MUX |--- out
 * in0 ------| 0   |
 *           +--+--+
 *         sel  |
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2014 Igor Lesik, MIT License
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
