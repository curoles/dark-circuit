/* CMOS Rising edge D Flip Flop with asynchronous clear, TSMC-style cell DFCNQ.
 *
 * Master-slave like DFQ, every latch is
 * Q = ((D & E) | (Q & ~E) | (D & Q)) & CDN, made of NAND cells,
 * so CDN=0 clears both latches without clock.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module DFCNQ (
    input  wire D,
    input  wire CP,  // clock
    input  wire CDN, // clear, active low
    output wire Q
);
    wire cp_n;
    wire m_q, m_de, m_qe, m_dq; // master latch
    wire s_de, s_qe, s_dq;      // slave latch

    INV u_inv(.I(CP), .ZN(cp_n));

    // Master latch, transparent while CP is 0.
    ND3 u_nd3_m_de(.A1(D),   .A2(cp_n), .A3(CDN), .ZN(m_de));
    ND3 u_nd3_m_qe(.A1(m_q), .A2(CP),   .A3(CDN), .ZN(m_qe));
    ND3 u_nd3_m_dq(.A1(D),   .A2(m_q),  .A3(CDN), .ZN(m_dq));
    ND3 u_nd3_m_q (.A1(m_de), .A2(m_qe), .A3(m_dq), .ZN(m_q));

    // Slave latch, transparent while CP is 1.
    ND3 u_nd3_s_de(.A1(m_q), .A2(CP),   .A3(CDN), .ZN(s_de));
    ND3 u_nd3_s_qe(.A1(Q),   .A2(cp_n), .A3(CDN), .ZN(s_qe));
    ND3 u_nd3_s_dq(.A1(m_q), .A2(Q),    .A3(CDN), .ZN(s_dq));
    ND3 u_nd3_s_q (.A1(s_de), .A2(s_qe), .A3(s_dq), .ZN(Q));

endmodule
