/* Half Adder, independent for every bit.
 *
 */
module HalfAdder #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire [WIDTH-1:0] sum,
    output wire [WIDTH-1:0] co   // carry out
);

    assign sum = in1 ^ in2;
    assign co  = in1 & in2;

endmodule
