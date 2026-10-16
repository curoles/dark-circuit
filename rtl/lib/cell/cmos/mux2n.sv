/* CMOS Inverting 2:1 Multiplexer, TSMC-style cell MUX2N.
 *
 * <pre>
 *    ---------+-------------+------ vdd
 *             |             |
 *     I1 +--o| p1   I0 +--o| p3
 *             |             |      pmos is open when gate 0
 *             |             |
 *     ~S +--o| p2    S +--o| p4
 *             |             |
 *             +-------------+------> ZN
 *             |             |
 *      S +---| n1   ~S +---| n3
 *             |             |      nmos is open when gate 1
 *             |             |
 *     I1 +---| n2   I0 +---| n4
 *             |             |
 *             |             |
 *           --+-------------+------ gnd
 * </pre>
 */
module MUX2N (
    input  wire I0,  // inverted to ZN when S is 0
    input  wire I1,  // inverted to ZN when S is 1
    input  wire S,
    output wire ZN
);

    supply1 vdd;
    supply0 gnd;

    wire s_n;
    INV u_inv_sel(.I(S), .ZN(s_n));

    wire p1_p2, p3_p4, n1_n2, n3_n4;

    // pmos drain source gate
    pmos p1(p1_p2,  vdd,   I1);
    pmos p2(ZN,   p1_p2,   s_n);

    pmos p3(p3_p4,  vdd,   I0);
    pmos p4(ZN,   p3_p4,   S);

    // nmos drain source gate
    nmos n1(ZN,   n1_n2,   S);
    nmos n2(n1_n2,  gnd,   I1);

    nmos n3(ZN,   n3_n4,   s_n);
    nmos n4(n3_n4,  gnd,   I0);

endmodule
