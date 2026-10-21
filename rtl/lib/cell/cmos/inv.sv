/* CMOS Inverter, TSMC-style cell INV.
 *
 * Use Verilog keywords `pmos` and `nmos` to define 2 transistors:
 *
 * ```verilog
 *  pmos p1 (ZN, vdd, I); // ZN = HI(vdd) if I is LO
 *  nmos n1 (ZN, gnd, I); // ZN = LO(gnd) if I is HI
 * ```
 *
 * See book by Yamin Li, Computer principles and design in Verilog HDL.
 *
 * <pre>
 *           +-------+-----+ vdd
 *                   |
 *               +   |
 *             + +---+
 *       +----o| |      p1
 *       |     + +---+
 *       |       +   |
 *       |           |
 *  I ---+           +------ ZN
 *       |           |
 *       |       +   |
 *       |     + +---+
 *       +-----+ |     n1
 *             + +---+
 *               +   |
 *                   |
 *                   |
 *         +---------+----+ gnd
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module INV (
    input  wire I,  // to be inverted
    output wire ZN  // ZN is inverted I
);
    supply1 vdd; // logic 1 (power)
    supply0 gnd; // logic 0 (ground)

    // pmos (drain, source, gate);
    pmos p1 (ZN, vdd, I);

    // nmos (drain, source, gate);
    nmos n1 (ZN, gnd, I);

endmodule
