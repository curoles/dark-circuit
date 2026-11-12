/* Packed multiply: the product of a and b in every 16-bit lane, 16 x 16 or of one byte pair,
 * or the dot product of every 32-bit group plus an accumulator; each operand signed or
 * unsigned, hybrid.
 *
 * A lane of 16 bits (a = {ah, al}, b = {bh, bl}) multiplies like 16 x 16 long
 * multiplication: 16 rows of partial-product bits, row j holding x & y[j], whose quadrants
 * are four 8 x 8 pieces: LL = al*bl, HL = ah*bl, LH = al*bh, HH = ah*bh (16 x 16 = LL +
 * (HL + LH) << 8 + HH << 16). Rows 0 to 7 (bl) multiply a 16-bit copy of a, xl, shifted by
 * j; rows 8 to 15 (bh) a 24-bit copy, xh, shifted by j - 8, where xh = {ah, al, 0} puts LH
 * at weight 8 and HH at 16. The mode picks the pieces by what goes into the copies: a piece
 * whose byte is 0 there gives 0, and HH moves to weight 0 when ah sits at the bottom of xh.
 * The selects are at the operands, before the partial products; no bit is masked or moved
 * after them. Signs by Baugh-Wooley, per piece: a piece whose a byte is signed has the bits
 * of that byte's sign bit negative, likewise for b (both: their common bit positive again);
 * a negative bit t is (~t) - 1, so those bits are inverted (where the piece sits in this
 * mode) and every piece adds a constant, minus the sum of the weights it inverted. One
 * constant row per lane holds the active pieces' constants modulo 2^32. A lane's rows go
 * into its WallaceTree; its adder gives the lane's product, exact in 32 bits, at bit 32k of
 * product.
 *
 * Modes (PackedPkg::mul_e): MUL_16, the four pieces, a signed 16-bit operand being a signed
 * high byte and an unsigned low byte (HL takes a_signed, LH b_signed, HH both, LL neither);
 * the byte modes MUL_B00 al*bl, MUL_B11 ah*bh, MUL_B01 al*bh (RISC-V P pmul.h.b00, b11, b01),
 * one piece: the selected bytes in LL's place with both flags; MUL_DOT_B (pm4add.b), LL
 * (xl = {0, al}) and HH at weight 0 (xh = {0, 0, ah}) with both flags, so a lane's rows sum
 * to al*bl + ah*bh; MUL_DOT_H (pm2add.h), the lanes' 16 x 16 products. In the dot modes the
 * accumulator (acc_en) is one more row of the first lane of every 32-bit group, and the two
 * lanes' trees are added in carry-save form, their four rows into a WallaceTree and one
 * adder: the group's dot product modulo 2^32 at bit 32g of dot (product is then not
 * meaningful, nor dot in the other modes). WIDTH 32 or 64. Hybrid (AGENTS.md): the trees
 * and the adders are library blocks; the partial-product bits, the selects and the
 * constants are glue.
 *
 * Pipeline: STAGES 0 is combinational (clk, rst_n, in_valid unused for data); STAGES 1 puts
 * a register after the lanes' trees, a DelayLine of the boundary struct (their sum and
 * carry rows), and product, dot and out_valid come one rising edge after the inputs and
 * in_valid; a new operation may enter every clock (no stall: a core that holds an operation
 * holds its inputs). Everything after the boundary reads only the struct: the dot product's
 * tree takes the rows, the accumulator having gone into the first lane's tree.
 *
 *   a (by mode) --> xl, xh;  b (by mode) --> y
 *   rows j < 8: (xl & y[j]) << j;  rows j >= 8: (xh & y[j]) << (j - 8);  sign bits inverted
 *   16 rows + constant (+ acc) --> lane WallaceTree --> sum, carry
 *   ---- stage boundary (STAGES 1): every lane's sum and carry ----
 *   lane's sum, carry --> adder --> product
 *   two lanes' sum, carry --> WallaceTree (4 rows) --> KoggeStoneAdder --> dot
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module PackedMul import PackedPkg::*; #(
    parameter int WIDTH  = 32,
    parameter int STAGES = 0                // pipeline stages: 0 (combinational) or 1
)(
    input  wire                clk,
    input  wire                rst_n,       // synchronous reset, active low: out_valid 0
    input  wire                in_valid,    // the inputs are an operation
    input  wire  [WIDTH-1:0]   a,
    input  wire  [WIDTH-1:0]   b,
    input  wire                a_signed,
    input  wire                b_signed,
    input  mul_e               mode,
    input  wire  [WIDTH-1:0]   acc,         // dot modes: added to group g's sum, bits 32g
    input  wire                acc_en,      // add acc, else 0
    output wire  [2*WIDTH-1:0] product,     // lane k (16 bits): its 32-bit product at bit 32k
    output wire  [WIDTH-1:0]   dot,         // dot modes: group g's dot product at bit 32g
    output wire                out_valid    // product and dot are the operation's, STAGES later
);
    localparam int LANES  = WIDTH / 16;
    localparam int GROUPS = WIDTH / 32;

    `DC_STATIC_ASSERT(a_width, WIDTH == 32 || WIDTH == 64)
    `DC_STATIC_ASSERT(a_stages, STAGES == 0 || STAGES == 1)

    // After the lanes' trees: their two rows, all the rest reads.
    typedef struct packed {
        logic [LANES-1:0][31:0] sum;
        logic [LANES-1:0][31:0] carry;
    } stage_boundary_tree_t;

    stage_boundary_tree_t tree_in;      // before the boundary
    stage_boundary_tree_t tree;         // after it: the only one the adders read

    // Pieces by index {b high byte, a high byte}: 0 LL, 1 HL, 2 LH, 3 HH.

    // A piece's bit is inverted: the piece is active and exactly one of its signed operands
    // has its sign bit there (i, j: the bit's place in the piece, 0 to 7).
    function automatic logic inverted(logic [1:0] p, int i, int j, logic [3:0] active,
                                      logic [3:0] fa, logic [3:0] fb);
        return active[p] && ((i == 7 && fa[p]) != (j == 7 && fb[p]));
    endfunction

    // Bit i of row j < 8 (xl): LL below bit 8, HL above.
    function automatic logic inverted_low(int i, int j, logic [3:0] active, logic [3:0] fa,
                                          logic [3:0] fb);
        return inverted(2'(i / 8), i % 8, j, active, fa, fb);
    endfunction

    // Bit i of row j >= 8 (xh): LH at bits 8 to 15 and HH at 16 to 23, or HH at bits 0 to 7
    // for the byte dot product.
    function automatic logic inverted_high(int i, int j, logic dot_b, logic [3:0] active,
                                           logic [3:0] fa, logic [3:0] fb);
        if (dot_b)
            return i < 8 && inverted(2'd3, i, j - 8, active, fa, fb);
        if (i >= 16)
            return inverted(2'd3, i - 16, j - 8, active, fa, fb);
        return i >= 8 && inverted(2'd2, i - 8, j - 8, active, fa, fb);
    endfunction

    // The sum of the weights a piece inverts, by its flags: a's sign bit times every bit of
    // b (or the reverse), and with both signed the two lines without their common bit.
    function automatic logic [31:0] inverted_weight(logic fa, logic fb);
        if (fa && fb) return 32'(1 << 8) * 32'((1 << 7) - 1);
        if (fa || fb) return 32'(1 << 7) * 32'((1 << 8) - 1);
        return '0;
    endfunction

    // The lane's constant row: minus the inverted weights of the active pieces at their
    // weights (LL 0, HL and LH 8, HH 16, or 0 for the byte dot product), modulo 2^32.
    function automatic logic [31:0] lane_constant(logic [3:0] active, logic [3:0] fa,
                                                  logic [3:0] fb, logic dot_b);
        logic [31:0] s;
        s = '0;
        for (int p = 0; p < 4; p++)
            if (active[p])
                s += inverted_weight(fa[p], fb[p]) <<
                     ((p == 3 && dot_b) ? 0 : 8 * (p / 2 + p % 2));
        return -s;
    endfunction

    logic       bytes;      // one byte pair per lane (MUL_B00, MUL_B11, MUL_B01)
    logic       dot_b;      // the byte dot product: LL and HH, HH at weight 0
    logic       dots;       // a dot product (MUL_DOT_B, MUL_DOT_H): the accumulator counts
    logic [3:0] active;     // the pieces in use
    logic [3:0] fa;         // a piece's a byte is signed
    logic [3:0] fb;         // a piece's b byte is signed

    // @kb: rtl/lib/numeric/packed/mul
    assign bytes = mode == MUL_B00 || mode == MUL_B11 || mode == MUL_B01;
    assign dot_b = mode == MUL_DOT_B;
    assign dots  = dot_b || mode == MUL_DOT_H;

    always_comb
        if (bytes) begin
            active = 4'b0001;
            fa     = {3'b000, a_signed};
            fb     = {3'b000, b_signed};
        end else if (dot_b) begin
            active = 4'b1001;
            fa     = {a_signed, 1'b0, 1'b0, a_signed};
            fb     = {b_signed, 1'b0, 1'b0, b_signed};
        end else begin          // MUL_16, MUL_DOT_H
            active = 4'b1111;
            fa     = {a_signed, 1'b0, a_signed, 1'b0};
            fb     = {b_signed, b_signed, 1'b0, 1'b0};
        end

    for (genvar k = 0; k < LANES; k++) begin : g_lane
        localparam int ROWS = (k % 2 == 0) ? 18 : 17;   // a group's first lane: + acc
        logic [7:0]  al;
        logic [7:0]  ah;
        logic [7:0]  bl;
        logic [7:0]  bh;
        logic [7:0]  xa;            // byte modes: a's byte of the pair
        logic [7:0]  yb;            // b's
        logic [15:0] xl;            // a for rows 0 to 7
        logic [23:0] xh;            // a for rows 8 to 15
        logic [15:0] y;             // b: bit j for row j
        logic [31:0] rows [ROWS];

        assign {ah, al} = a[16*k +: 16];
        assign {bh, bl} = b[16*k +: 16];
        assign xa = mode == MUL_B11 ? ah : al;
        assign yb = mode == MUL_B00 ? bl : bh;
        assign xl = bytes ? {8'b0, xa} : dot_b ? {8'b0, al} : {ah, al};
        assign xh = dot_b ? {16'b0, ah} : {ah, al, 8'b0};
        assign y  = bytes ? {8'b0, yb} : {bh, bl};

        for (genvar j = 0; j < 8; j++) begin : g_row_low
            logic [15:0] pp;
            for (genvar i = 0; i < 16; i++) begin : g_bit
                assign pp[i] = (xl[i] & y[j]) ^ inverted_low(i, j, active, fa, fb);
            end
            assign rows[j] = 32'(pp) << j;
        end
        for (genvar j = 8; j < 16; j++) begin : g_row_high
            logic [23:0] pp;
            for (genvar i = 0; i < 24; i++) begin : g_bit
                assign pp[i] = (xh[i] & y[j]) ^ inverted_high(i, j, dot_b, active, fa, fb);
            end
            assign rows[j] = 32'(pp) << (j - 8);
        end
        assign rows[16] = lane_constant(active, fa, fb, dot_b);
        if (k % 2 == 0) begin : g_acc
            assign rows[17] = (dots && acc_en) ? acc[16*k +: 32] : '0;
        end

        WallaceTree #(.ROWS(ROWS), .WIDTH(32)) u_wallace_tree(
            .rows, .sum(tree_in.sum[k]), .carry(tree_in.carry[k]));
    end

    DelayLine #(.WIDTH($bits(stage_boundary_tree_t)), .DEPTH(STAGES))
        u_stage_boundary_tree(.clk, .rst_n, .in(tree_in), .out(tree));

    // The operation's valid bit, STAGES clocks later; 0 after reset.
    DelayLine #(.WIDTH(1), .DEPTH(STAGES), .RESET(1)) u_valid(
        .clk, .rst_n, .in(in_valid), .out(out_valid));

    // Product modes: every lane's two rows added.
    for (genvar k = 0; k < LANES; k++) begin : g_product
        // The carry out has weight 2^32: not part of the 32-bit product.
        /* verilator lint_off UNUSEDSIGNAL */
        logic co;
        /* verilator lint_on UNUSEDSIGNAL */
        KoggeStoneAdder #(.WIDTH(32)) u_kogge_stone_adder(
            .in1(tree.sum[k]), .in2(tree.carry[k]), .ci(1'b0), .co,
            .sum(product[32*k +: 32]));
    end

    // Dot modes: the two lanes of a 32-bit group in carry-save form into one more tree, one
    // adder (the accumulator is already in the first lane's tree).
    for (genvar g = 0; g < GROUPS; g++) begin : g_group
        logic [31:0] rows [4];
        logic [31:0] sum;
        logic [31:0] carry;
        // The carry out has weight 2^32: the dot product is modulo 2^32.
        /* verilator lint_off UNUSEDSIGNAL */
        logic        co;
        /* verilator lint_on UNUSEDSIGNAL */

        assign rows[0] = tree.sum[2 * g];
        assign rows[1] = tree.carry[2 * g];
        assign rows[2] = tree.sum[2 * g + 1];
        assign rows[3] = tree.carry[2 * g + 1];

        WallaceTree #(.ROWS(4), .WIDTH(32)) u_wallace_tree(.rows, .sum, .carry);
        KoggeStoneAdder #(.WIDTH(32)) u_kogge_stone_adder(
            .in1(sum), .in2(carry), .ci(1'b0), .co, .sum(dot[32*g +: 32]));
    end

endmodule
