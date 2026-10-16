/* CMOS Full Adder using And-Or-Invert (AOI) logic, TSMC-style cell FA1.
 *
 * Author: Igor Lesik 2020.
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
 */
module FA1 (
    input  wire A,
    input  wire B,
    input  wire CI, // carry in
    output wire S,  // sum
    output wire CO  // carry out
);
    wire ab_or, abc_or, bc_and;
    wire co_n, sum_n;

    OR2   u_or2(.A1(A), .A2(B), .Z(ab_or));
    OR3   u_or3(.A1(A), .A2(B), .A3(CI), .Z(abc_or));
    AN2   u_an2(.A1(B), .A2(CI), .Z(bc_and));

    AOI22 u_aoi22_co (.A1(ab_or), .A2(CI), .B1(A), .B2(B), .ZN(co_n));
    INV   u_inv_co   (.I(co_n), .ZN(CO));

    AOI22 u_aoi22_sum(.A1(co_n), .A2(abc_or), .B1(A), .B2(bc_and), .ZN(sum_n));
    INV   u_inv_sum  (.I(sum_n), .ZN(S));

endmodule
