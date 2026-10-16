/* CMOS AND-OR-Invert, TSMC-style cell AOI31, ZN = ~((A1 & A2 & A3) | B).
 *
 * <pre>
 *  pull-up:    vdd --+-- p1(A1) --+-- p4(B) -- ZN
 *                    +-- p2(A2) --+
 *                    +-- p3(A3) --+
 *
 *  pull-down:  ZN --+-- n1(A1) -- n2(A2) -- n3(A3) --+-- gnd
 *                   +-- n4(B) -----------------------+
 * </pre>
 */
module AOI31 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    input  wire B,
    output wire ZN
);

    supply1 vdd;
    supply0 gnd;

    wire w_p;        // connects parallel pmos A1, A2, A3 to pmos B
    wire w_n1, w_n2; // connect nmos A1, A2, A3 in series

    // pmos drain source gate
    pmos p1(w_p,  vdd,   A1);
    pmos p2(w_p,  vdd,   A2);
    pmos p3(w_p,  vdd,   A3);
    pmos p4(ZN,   w_p,   B);

    // nmos drain source gate
    nmos n1(ZN,   w_n1,  A1);
    nmos n2(w_n1, w_n2,  A2);
    nmos n3(w_n2, gnd,   A3);
    nmos n4(ZN,   gnd,   B);

endmodule
