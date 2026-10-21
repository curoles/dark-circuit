/* CMOS 2-input NAND, TSMC-style cell ND2.
 *
 * <pre>
 *    ---------+-------------+------ vdd
 *             |             |
 *       +--o| p1      +--o| p2
 *       |     |       |     |
 *       |     +-------------+------ ZN
 *       |             |     |
 *  A1 --+-----------------| n1
 *                     |     |
 *  A2 ----------------+---| n2
 *                           |
 *                   --------+------ gnd
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module ND2 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    supply1 vdd;
    supply0 gnd;

    wire w_n; // connects 2 nmos transistors

    // pmos drain source gate
    pmos p1(ZN,   vdd,   A1);
    pmos p2(ZN,   vdd,   A2);

    // nmos drain source gate
    nmos n1(ZN,   w_n,   A1);
    nmos n2(w_n,  gnd,   A2);

endmodule
