/* Full Adder made of MAJ3 gates and inverters only, independent for every bit.
 *
 * Author: Igor Lesik
 *
 * M1  = MAJ3(A, B, Cin)         -> Cout
 * M2  = MAJ3(A, B, NOT(Cin))    -> intermediate
 * Sum = MAJ3(NOT(M1), M2, Cin)  -> Sum
 *
 * See article:
 * https://www.linkedin.com/pulse/full-adder-maj3-gates-igor-lesik-n0wtc/
 */
module FullAdderMaj3 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] ci,  // carry in
    output wire [WIDTH-1:0] sum,
    output wire [WIDTH-1:0] co   // carry out
);
    wire [WIDTH-1:0] ci_n, co_n, m2;

    // M1 = MAJ3(A, B, Cin) is carry out.
    Maj3 #(WIDTH) u_maj3_co (.in1(in1), .in2(in2), .in3(ci), .out(co));

    // M2 = MAJ3(A, B, ~Cin).
    Inv  #(WIDTH) u_inv_ci  (.in(ci), .out(ci_n));
    Maj3 #(WIDTH) u_maj3_m2 (.in1(in1), .in2(in2), .in3(ci_n), .out(m2));

    // Sum = MAJ3(~M1, M2, Cin).
    Inv  #(WIDTH) u_inv_co  (.in(co), .out(co_n));
    Maj3 #(WIDTH) u_maj3_sum(.in1(co_n), .in2(m2), .in3(ci), .out(sum));

endmodule
