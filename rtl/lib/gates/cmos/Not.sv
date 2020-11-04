/* CMOS Inverter gate.
 *
 * Use Verilog keywords `pmos` and `nmos` to define 2 transistors:
 *
 * ```verilog
 *  pmos p1 (out, vdd, in); // out = HI(vdd) if in is LO
 *  nmos n1 (out, gnd, in); // out = LO(gnd) if in is HI
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
 *  +----+           +------+
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
 */
module Not(
    output wire out, // out = ~in
    input wire in
);
    supply1 vdd; // logic 1 (power)
    supply0 gnd; // logic 0 (ground)

    // pmos (drain, source, gate);
    pmos p1 (out, vdd, in);

    // nmos (drain, source, gate);
    nmos n1 (out, gnd, in);

endmodule
