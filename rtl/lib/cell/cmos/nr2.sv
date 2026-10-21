/* CMOS 2-input NOR, TSMC-style cell NR2.
 *
 * <pre>
 *              -------------+------ vdd
 *                           |
 *  A1 ----+--------------o| p1
 *         |                 |
 *  A2 -------------+-----o| p2
 *         |        |        |
 *         |   +-------------+------ ZN
 *         |   |    |        |
 *         +-| n1   +------| n2
 *             |             |
 *          ---+-------------+---- gnd
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module NR2 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    supply1 vdd;
    supply0 gnd;

    wire w_p; // connects 2 pmos transistors

    // nmos drain source gate
    nmos n1(ZN,   gnd,   A1);
    nmos n2(ZN,   gnd,   A2);

    // pmos drain source gate
    pmos p1(w_p,  vdd,   A1);
    pmos p2(ZN,   w_p,   A2);

endmodule
