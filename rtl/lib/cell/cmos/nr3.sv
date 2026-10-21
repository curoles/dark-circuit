/* CMOS 3-input NOR, TSMC-style cell NR3.
 *
 * <pre>
 *              -------------------------+------ vdd
 *                                       |
 *  A1 ----+--------------------------o| p1
 *         |                             |
 *  A2 -------------+-----------------o| p2
 *         |        |                    |
 *  A3 ----------------------+--------o| p3
 *         |        |        |           |
 *         |   +--------+--------+-------+------ ZN
 *         |   |    |   |    |   |
 *         +-| n1   +-| n2   +-| n3
 *             |        |        |
 *          ---+--------+--------+---- gnd
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module NR3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire ZN
);

    supply1 vdd;
    supply0 gnd;

    wire w_p1, w_p2; // connect 3 pmos transistors in series

    // nmos drain source gate
    nmos n1(ZN,   gnd,   A1);
    nmos n2(ZN,   gnd,   A2);
    nmos n3(ZN,   gnd,   A3);

    // pmos drain source gate
    pmos p1(w_p1, vdd,   A1);
    pmos p2(w_p2, w_p1,  A2);
    pmos p3(ZN,   w_p2,  A3);

endmodule
