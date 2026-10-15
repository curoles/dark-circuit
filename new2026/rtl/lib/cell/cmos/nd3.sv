/* CMOS 3-input NAND, TSMC-style cell ND3.
 *
 * <pre>
 *    ---------+-------------+-------------+------ vdd
 *             |             |             |
 *       +--o| p1      +--o| p2      +--o| p3
 *       |     |       |     |       |     |
 *       |     +-------------+-------------+------ ZN
 *       |             |             |     |
 *  A1 --+---------------------------------| n1
 *                     |             |     |
 *  A2 ----------------+-------------------| n2
 *                                   |     |
 *  A3 ------------------------------+---| n3
 *                                         |
 *                                 --------+------ gnd
 * </pre>
 */
module ND3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire ZN
);

    supply1 vdd;
    supply0 gnd;

    wire w_n1, w_n2; // connect 3 nmos transistors in series

    // pmos drain source gate
    pmos p1(ZN,   vdd,   A1);
    pmos p2(ZN,   vdd,   A2);
    pmos p3(ZN,   vdd,   A3);

    // nmos drain source gate
    nmos n1(ZN,   w_n1,  A1);
    nmos n2(w_n1, w_n2,  A2);
    nmos n3(w_n2, gnd,   A3);

endmodule
