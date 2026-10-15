/* Full Adder, independent for every bit (no carry chain between bits).
 *
 */
module FullAdder #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] ci,  // carry in
    output wire [WIDTH-1:0] sum,
    output wire [WIDTH-1:0] co   // carry out
);

    assign sum = in1 ^ in2 ^ ci;
    assign co  = (in1 & in2) | (ci & (in1 | in2));

endmodule
