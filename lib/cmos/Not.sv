/**
 * @brief CMOS inverter
 *
 * See book by Yamin Li, Computer principles and design in Verilog HDL.
 *  
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
 *  
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
