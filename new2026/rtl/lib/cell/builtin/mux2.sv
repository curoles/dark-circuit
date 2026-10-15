/* Multiplexer made with Verilog primitives `nand` and `not`, TSMC-style cell MUX2.
 *
 * Author: Igor Lesik 2020.
 *
 * <pre>
 *                  +------+
 *                  |      |
 *  I1  +-----------+ NAND |
 *                  |      |o+-+    +------+
 *  S   +-----+-----+      |   |    |      |
 *            |     |      |   |    |      |
 *            |     +------+   +----+ NAND |
 *            |                     |      |o+----+ Z
 *            |     +------+   +----+      |
 *            |     |      |   |    |      |
 *            +---+o| NAND |   |    |      |
 *                  |      |o+-+    +------+
 *  I0  +-----------+      |
 *                  |      |
 *                  +------+
 *  </pre>
 */
module MUX2 (
    input  wire I0,  // selected when S is 0
    input  wire I1,  // selected when S is 1
    input  wire S,
    output wire Z
);

    wire s_n, o1, o0;

    not  u_not_sel(s_n, S);
    nand u_nand_1(o1, I1, S);
    nand u_nand_0(o0, I0, s_n);
    nand u_nand_out(Z, o1, o0);

endmodule
