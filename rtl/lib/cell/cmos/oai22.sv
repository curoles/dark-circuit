/* CMOS OR-AND-Invert, TSMC-style cell OAI22, ZN = ~((A1 | A2) & (B1 | B2)).
 *
 * <pre>
 *  pull-up:    vdd --+-- p1(A1) -- p2(A2) --+-- ZN
 *                    +-- p3(B1) -- p4(B2) --+
 *
 *  pull-down:  ZN --+-- n1(A1) --+--+-- n3(B1) --+-- gnd
 *                   +-- n2(A2) --+  +-- n4(B2) --+
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module OAI22 (
    input  wire A1,
    input  wire A2,
    input  wire B1,
    input  wire B2,
    output wire ZN
);

    supply1 vdd;
    supply0 gnd;

    wire w_p1; // connects pmos A1, A2 in series
    wire w_p2; // connects pmos B1, B2 in series
    wire w_n;  // connects parallel nmos A1, A2 to parallel nmos B1, B2

    // pmos drain source gate
    pmos p1(w_p1, vdd,   A1);
    pmos p2(ZN,   w_p1,  A2);
    pmos p3(w_p2, vdd,   B1);
    pmos p4(ZN,   w_p2,  B2);

    // nmos drain source gate
    nmos n1(ZN,   w_n,   A1);
    nmos n2(ZN,   w_n,   A2);
    nmos n3(w_n,  gnd,   B1);
    nmos n4(w_n,  gnd,   B2);

endmodule
