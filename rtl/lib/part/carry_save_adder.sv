/* Carry Save Adder: adds 3 numbers into partial sum and shifted carry,
 * in1 + in2 + in3 = ps + (sc << 1).
 *
 * Row of independent full adders, no carry chain.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module CarrySaveAdder #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] in3,
    output wire [WIDTH-1:0] ps,  // partial sum
    output wire [WIDTH-1:0] sc   // shift-carry, has weight 2
);

    FullAdder #(WIDTH) u_full_adder(.in1(in1), .in2(in2), .ci(in3), .sum(ps), .co(sc));

endmodule
