/* Full Adder using And-Or-Invert (AOI) logic, independent for every bit.
 *
 * AOI logic is a technique of using equivalent Boolean logic expressions
 * to reduce the number of gates required for a particular expression.
 * This, in turn, reduces capacitance and consequently propagation times.
 *
 * For this design, AOI logic has been applied to the calculation of the *Sum* bit:
 *
 * Sumₖ = Aₖ ⊕ Bₖ ⊕ Cₖ = (Aₖ + Bₖ + Cₖ)~Cₖ₊₁ + AₖBₖCₖ
 *
 * where Cₖ₊₁ = AₖBₖ + Cₖ(Aₖ + Bₖ)
 *
 * Instead of using two XOR gates to implement the Sum bit,
 * the circuit takes advantage of the fact that ~Cₖ₊₁ already computed
 * and uses fewer gates to calculate the rest of the expression.
 *
 * @author    Igor Lesik
 * @copyright 2020 Igor Lesik, MIT License
 */
module FullAdderAoi #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] ci,  // carry in
    output wire [WIDTH-1:0] sum,
    output wire [WIDTH-1:0] co   // carry out
);
    wire [WIDTH-1:0] ab_or, abc_or, bc_and, co_n, sum_n;

    Or2   #(WIDTH) u_or2      (.in1(in1), .in2(in2), .out(ab_or));
    Or3   #(WIDTH) u_or3      (.in1(in1), .in2(in2), .in3(ci), .out(abc_or));
    And2  #(WIDTH) u_and2     (.in1(in2), .in2(ci), .out(bc_and));

    Aoi22 #(WIDTH) u_aoi22_co (.in1(ab_or), .in2(ci), .in3(in1), .in4(in2), .out(co_n));
    Inv   #(WIDTH) u_inv_co   (.in(co_n), .out(co));

    Aoi22 #(WIDTH) u_aoi22_sum(.in1(co_n), .in2(abc_or), .in3(in1), .in4(bc_and), .out(sum_n));
    Inv   #(WIDTH) u_inv_sum  (.in(sum_n), .out(sum));

endmodule
