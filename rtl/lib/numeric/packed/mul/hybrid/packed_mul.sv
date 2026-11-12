/* Packed multiply: the product of a and b in every 16-bit lane, 16 x 16 or of one byte pair,
 * each operand signed or unsigned, hybrid.
 *
 * Every lane of 16 bits (a = {ah, al}, b = {bh, bl}) is a 16 x 16 array of partial-product
 * bits x[i] & y[j] at weight i + j, in 16 rows (row j: bit j of y), whose quadrants are four
 * 8 x 8 pieces: LL = al*bl, HL = ah*bl, LH = al*bh, HH = ah*bh (16 x 16 = LL + (HL + LH) << 8
 * + HH << 16). Signs by Baugh-Wooley, per piece: a piece whose a byte is signed has the bits
 * of that byte's sign bit negative, likewise for b (both: their common bit positive again);
 * a negative bit t is (~t) - 1, so those bits are inverted and every piece adds a constant,
 * minus the sum of the weights it inverted. One constant row per lane holds the sum of the
 * active pieces' constants (a function of mode and the flags), modulo 2^32: the lane's
 * product comes out exact in 32 bits, lane k's at bit 32k of product. 17 rows, the size of
 * a plain 16 x 16 array, and no correction rows of data.
 *
 * Modes: MUL_16, the four pieces, a signed 16-bit operand being a signed high byte and an
 * unsigned low byte (HL takes a_signed, LH b_signed, HH both, LL neither); the byte modes,
 * one piece: LL takes the selected bytes (MUL_B00 al*bl, MUL_B11 ah*bh, MUL_B01 al*bh, RISC-V
 * P pmul.h.b00, b11, b01) with both flags, the other three are not active (operands 0, no
 * inverted bits, no constant). Dot products and an accumulator come later, from the same
 * pieces (kb rtl/lib/numeric/packed/mul). WIDTH 32 or 64. Hybrid (AGENTS.md): the tree and
 * the adder are library blocks; the partial-product bits, the selects and the constant are
 * glue.
 *
 *   x, y (by mode) --> bit (i, j) = x[i] & y[j], inverted at the active pieces' sign bits
 *   16 rows + the constant row --> WallaceTree --> sum, carry --> KoggeStoneAdder --> lane
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module PackedMul import PackedPkg::*; #(
    parameter int WIDTH = 32
)(
    input  wire  [WIDTH-1:0]   a,
    input  wire  [WIDTH-1:0]   b,
    input  wire                a_signed,
    input  wire                b_signed,
    input  mul_e               mode,
    output wire  [2*WIDTH-1:0] product      // lane k (16 bits): its 32-bit product at bit 32k
);
    localparam int LANES = WIDTH / 16;

    `DC_STATIC_ASSERT(a_width, WIDTH == 32 || WIDTH == 64)

    // Pieces by index {b high byte, a high byte}: 0 LL, 1 HL, 2 LH, 3 HH.

    // The bit (i, j) of a lane's array is inverted: its piece is active and exactly one of
    // the piece's signed operands has its sign bit there.
    function automatic logic inverted(int i, int j, logic [3:0] active, logic [3:0] fa,
                                      logic [3:0] fb);
        logic [1:0] p;          // the piece
        p = 2'(2 * (j / 8) + i / 8);
        return active[p] && ((i % 8 == 7 && fa[p]) != (j % 8 == 7 && fb[p]));
    endfunction

    // The sum of the weights a piece inverts, by its flags: a's sign bit times every bit of
    // b (or the reverse), and with both signed the two lines without their common bit.
    function automatic logic [31:0] inverted_weight(logic fa, logic fb);
        if (fa && fb) return 32'(1 << 8) * 32'((1 << 7) - 1);
        if (fa || fb) return 32'(1 << 7) * 32'((1 << 8) - 1);
        return '0;
    endfunction

    // The lane's constant row: minus the inverted weights of the active pieces at their
    // weights (LL 0, HL and LH 8, HH 16), modulo 2^32.
    function automatic logic [31:0] lane_constant(logic [3:0] active, logic [3:0] fa,
                                                  logic [3:0] fb);
        logic [31:0] s;
        s = '0;
        for (int p = 0; p < 4; p++)
            if (active[p])
                s += inverted_weight(fa[p], fb[p]) << (8 * (p / 2 + p % 2));
        return -s;
    endfunction

    logic       bytes;      // one byte pair per lane, else 16 x 16
    logic [3:0] active;     // the pieces in use
    logic [3:0] fa;         // a piece's a byte is signed
    logic [3:0] fb;         // a piece's b byte is signed

    // @kb: rtl/lib/numeric/packed/mul
    assign bytes  = mode != MUL_16;
    assign active = bytes ? 4'b0001 : 4'b1111;
    assign fa     = bytes ? {3'b000, a_signed} : {a_signed, 1'b0, a_signed, 1'b0};
    assign fb     = bytes ? {3'b000, b_signed} : {b_signed, b_signed, 1'b0, 1'b0};

    for (genvar k = 0; k < LANES; k++) begin : g_lane
        logic [7:0]  al;
        logic [7:0]  ah;
        logic [7:0]  bl;
        logic [7:0]  bh;
        logic [7:0]  xa;            // byte modes: a's byte of the pair
        logic [7:0]  yb;            // b's
        logic [15:0] x;             // the array's operands
        logic [15:0] y;
        logic [31:0] rows [17];
        logic [31:0] sum;
        logic [31:0] carry;
        // The carry out has weight 2^32: not part of the 32-bit product.
        /* verilator lint_off UNUSEDSIGNAL */
        logic        co;
        /* verilator lint_on UNUSEDSIGNAL */

        assign {ah, al} = a[16*k +: 16];
        assign {bh, bl} = b[16*k +: 16];
        assign xa = mode == MUL_B11 ? ah : al;
        assign yb = mode == MUL_B00 ? bl : bh;
        assign x  = bytes ? {8'b0, xa} : {ah, al};
        assign y  = bytes ? {8'b0, yb} : {bh, bl};

        for (genvar j = 0; j < 16; j++) begin : g_row
            logic [15:0] pp;        // x & y[j], the inverted bits flipped
            for (genvar i = 0; i < 16; i++) begin : g_bit
                assign pp[i] = (x[i] & y[j]) ^ inverted(i, j, active, fa, fb);
            end
            assign rows[j] = 32'(pp) << j;
        end
        assign rows[16] = lane_constant(active, fa, fb);

        WallaceTree #(.ROWS(17), .WIDTH(32)) u_wallace_tree(.rows, .sum, .carry);
        KoggeStoneAdder #(.WIDTH(32)) u_kogge_stone_adder(
            .in1(sum), .in2(carry), .ci(1'b0), .co, .sum(product[32*k +: 32]));
    end

endmodule
