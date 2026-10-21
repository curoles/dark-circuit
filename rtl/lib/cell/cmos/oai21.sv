/* CMOS OR-AND-Invert, TSMC-style cell OAI21, ZN = ~((A1 | A2) & B).
 *
 * <pre>
 *  pull-up:    vdd --+-- p1(A1) -- p2(A2) --+-- ZN
 *                    +-- p3(B) -------------+
 *
 *  pull-down:  ZN -- n3(B) --+-- n1(A1) --+-- gnd
 *                            +-- n2(A2) --+
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module OAI21 (
    input  wire A1,
    input  wire A2,
    input  wire B,
    output wire ZN
);

    supply1 vdd;
    supply0 gnd;

    wire w_p; // connects pmos A1, A2 in series
    wire w_n; // connects nmos B to parallel nmos A1, A2

    // pmos drain source gate
    pmos p1(w_p,  vdd,   A1);
    pmos p2(ZN,   w_p,   A2);
    pmos p3(ZN,   vdd,   B);

    // nmos drain source gate
    nmos n3(ZN,   w_n,   B);
    nmos n1(w_n,  gnd,   A1);
    nmos n2(w_n,  gnd,   A2);

endmodule
