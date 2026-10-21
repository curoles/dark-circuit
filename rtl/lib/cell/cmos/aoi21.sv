/* CMOS AND-OR-Invert, TSMC-style cell AOI21, ZN = ~((A1 & A2) | B).
 *
 * <pre>
 *  pull-up:    vdd --+-- p1(A1) --+-- p3(B) -- ZN
 *                    +-- p2(A2) --+
 *
 *  pull-down:  ZN --+-- n1(A1) -- n2(A2) --+-- gnd
 *                   +-- n3(B) -------------+
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module AOI21 (
    input  wire A1,
    input  wire A2,
    input  wire B,
    output wire ZN
);

    supply1 vdd;
    supply0 gnd;

    wire w_p; // connects parallel pmos A1, A2 to pmos B
    wire w_n; // connects nmos A1, A2 in series

    // pmos drain source gate
    pmos p1(w_p,  vdd,   A1);
    pmos p2(w_p,  vdd,   A2);
    pmos p3(ZN,   w_p,   B);

    // nmos drain source gate
    nmos n1(ZN,   w_n,   A1);
    nmos n2(w_n,  gnd,   A2);
    nmos n3(ZN,   gnd,   B);

endmodule
