/* CMOS AND-OR-Invert, TSMC-style cell AOI22, ZN = ~((A1 & A2) | (B1 & B2)).
 *
 * <pre>
 *  pull-up:    vdd --+-- p1(A1) --+--+-- p3(B1) --+-- ZN
 *                    +-- p2(A2) --+  +-- p4(B2) --+
 *
 *  pull-down:  ZN --+-- n1(A1) -- n2(A2) --+-- gnd
 *                   +-- n3(B1) -- n4(B2) --+
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module AOI22 (
    input  wire A1,
    input  wire A2,
    input  wire B1,
    input  wire B2,
    output wire ZN
);

    supply1 vdd;
    supply0 gnd;

    wire w_p;  // connects parallel pmos A1, A2 to parallel pmos B1, B2
    wire w_n1; // connects nmos A1, A2 in series
    wire w_n2; // connects nmos B1, B2 in series

    // pmos drain source gate
    pmos p1(w_p,  vdd,   A1);
    pmos p2(w_p,  vdd,   A2);
    pmos p3(ZN,   w_p,   B1);
    pmos p4(ZN,   w_p,   B2);

    // nmos drain source gate
    nmos n1(ZN,   w_n1,  A1);
    nmos n2(w_n1, gnd,   A2);
    nmos n3(ZN,   w_n2,  B1);
    nmos n4(w_n2, gnd,   B2);

endmodule
