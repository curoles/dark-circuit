/* CMOS 2-input XOR, TSMC-style cell XOR2.
 *
 * Made of 4 NAND cells.
 *
 * <pre>
 *  A1 ---+------------+---\
 *        |            |ND2 o-- n2 ---\
 *        +---\   +----+---/           |
 *            |ND2 o--+                |ND2 o--- Z
 *        +---/   +----+---\           |
 *        |            |ND2 o-- n3 ---/
 *  A2 ---+------------+---/
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module XOR2 (
    input  wire A1,
    input  wire A2,
    output wire Z
);
    wire n1, n2, n3;
    ND2 u_nd2_1(.A1(A1), .A2(A2), .ZN(n1));
    ND2 u_nd2_2(.A1(A1), .A2(n1), .ZN(n2));
    ND2 u_nd2_3(.A1(A2), .A2(n1), .ZN(n3));
    ND2 u_nd2_4(.A1(n2), .A2(n3), .ZN(Z));

endmodule
