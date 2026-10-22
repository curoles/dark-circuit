/* Kogge-Stone adder: {co, sum} = in1 + in2 + ci, parallel prefix, made of gates.
 *
 * Same ports and result as RippleCarryAdder; the carries take log2(WIDTH) levels instead
 * of a chain of WIDTH full adders. Bit i generates a carry (g = in1 & in2) or propagates
 * one (p = in1 ^ in2); bit 0 also takes ci, g = Maj3(in1, in2, ci), so ci costs no extra
 * level. Level l combines every bit with the bit 2^l below it, a high span over the low
 * span below it: G = G_hi | P_hi & G_lo, P = P_hi & P_lo. After the last level G of bit i
 * is the carry out of bits i..0, and sum[i] = p[i] ^ carry into bit i. Every bit combines
 * at every level: fewest levels, most gates and wires (about WIDTH * log2(WIDTH) combines).
 *
 * - P. M. Kogge, H. S. Stone, A Parallel Algorithm for the Efficient Solution of a General
 *   Class of Recurrence Equations, IEEE Transactions on Computers, 1973.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module KoggeStoneAdder #(
    parameter WIDTH = 64
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire             ci,     // carry in
    output wire             co,     // carry out
    output wire [WIDTH-1:0] sum
);
    localparam LEVELS = $clog2(WIDTH);

    // g[l][i], p[l][i]: generate and propagate of the span of bits i down to i - 2^l + 1
    // (down to bit 0 when that is lower). P of a span that reaches bit 0 is not used: its
    // carry is its G. split_var: Verilator treats the elements separately, no false loop.
    wire [WIDTH-1:0] g [0:LEVELS] /*verilator split_var*/;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [WIDTH-1:0] p [0:LEVELS] /*verilator split_var*/;
    /* verilator lint_on UNUSEDSIGNAL */

    // Level 0: every bit alone; bit 0 includes ci.
    Xor2 #(WIDTH) u_xor2_p(.in1, .in2, .out(p[0]));
    Maj3 u_maj3_g(.in1(in1[0]), .in2(in2[0]), .in3(ci), .out(g[0][0]));
    if (WIDTH > 1) begin : g_wide
        And2 #(WIDTH-1) u_and2_g(.in1(in1[WIDTH-1:1]), .in2(in2[WIDTH-1:1]),
                                 .out(g[0][WIDTH-1:1]));
    end

    // Levels 1..LEVELS: combine with the span 2^l below; bits below 2^l already reach
    // bit 0 and pass on.
    for (genvar l = 0; l < LEVELS; l++) begin : g_level
        localparam D = 1 << l;
        for (genvar i = 0; i < WIDTH; i++) begin : g_bit
            if (i >= D) begin : g_combine
                wire pg;    // P_hi & G_lo
                And2 u_and2_0(.in1(p[l][i]), .in2(g[l][i-D]), .out(pg));
                Or2  u_or2   (.in1(g[l][i]), .in2(pg), .out(g[l+1][i]));
                And2 u_and2_1(.in1(p[l][i]), .in2(p[l][i-D]), .out(p[l+1][i]));
            end else begin : g_pass
                assign g[l+1][i] = g[l][i];
                assign p[l+1][i] = p[l][i];
            end
        end
    end

    // Sums: bit i adds the carry out of bits i-1..0 (ci into bit 0).
    Xor2 u_xor2_0(.in1(p[0][0]), .in2(ci), .out(sum[0]));
    if (WIDTH > 1) begin : g_sum
        Xor2 #(WIDTH-1) u_xor2_s(.in1(p[0][WIDTH-1:1]), .in2(g[LEVELS][WIDTH-2:0]),
                                 .out(sum[WIDTH-1:1]));
    end
    assign co = g[LEVELS][WIDTH-1];

endmodule
