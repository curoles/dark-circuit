/* CMOS Latch, transparent while E is 1, TSMC-style cell LHQ.
 *
 * Q = (D & E) | (Q & ~E) | (D & Q), made of NAND cells.
 *
 * Term D & Q keeps Q stable while E changes,
 * plain 2:1 MUX with feedback would glitch when E falls.
 */
module LHQ (
    input  wire D,
    input  wire E, // enable
    output wire Q
);
    wire e_n;
    wire t_de, t_qe, t_dq;

    INV u_inv(.I(E), .ZN(e_n));

    ND2 u_nd2_de(.A1(D), .A2(E),   .ZN(t_de));
    ND2 u_nd2_qe(.A1(Q), .A2(e_n), .ZN(t_qe));
    ND2 u_nd2_dq(.A1(D), .A2(Q),   .ZN(t_dq));
    ND3 u_nd3_q (.A1(t_de), .A2(t_qe), .A3(t_dq), .ZN(Q));

endmodule
