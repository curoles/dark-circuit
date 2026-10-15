/* 2-input OR.
 *
 */
module Or2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire [WIDTH-1:0] out
);

    assign out = in1 | in2;

endmodule
