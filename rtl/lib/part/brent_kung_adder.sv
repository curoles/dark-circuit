/* Brent-Kung adder: {co, sum} = in1 + in2 + ci, parallel prefix, made of gates.
 *
 * Same ports and result as RippleCarryAdder and KoggeStoneAdder. The carries take
 * 2*log2(WIDTH) - 1 levels with about 2*WIDTH combines, where KoggeStoneAdder takes
 * log2(WIDTH) levels with about WIDTH*log2(WIDTH): fewer gates and wires, more levels.
 * Bit i generates a carry (g = in1 & in2) or propagates one (p = in1 ^ in2); bit 0 also
 * takes ci, g = Maj3(in1, in2, ci). A combine of a high span over the low span below it:
 * G = G_hi | P_hi & G_lo, P = P_hi & P_lo. Up the tree, level l combines bit i with bit
 * i - 2^l when i + 1 is a multiple of 2^(l+1): spans of 2, 4, 8, ... bits, and bit
 * 2^k - 1 reaches bit 0. Down the tree, level l combines bit i with bit i - 2^l when
 * i + 1 is an odd multiple of 2^l (3, 5, ... times): bit i - 2^l already reaches bit 0,
 * so bit i does too. sum[i] = p[i] ^ carry into bit i.
 *
 * - R. P. Brent, H. T. Kung, A Regular Layout for Parallel Adders, IEEE Transactions on
 *   Computers, 1982.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module BrentKungAdder #(
    parameter WIDTH = 64
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire             ci,     // carry in
    output wire             co,     // carry out
    output wire [WIDTH-1:0] sum
);
    localparam LEVELS = $clog2(WIDTH);                      // levels up the tree
    localparam STAGES = LEVELS == 0 ? 0 : 2 * LEVELS - 1;   // up, then one level fewer down

    // g[s][i], p[s][i]: generate and propagate of the span of bit i after s stages. P of
    // a span that reaches bit 0 is not used: its carry is its G. split_var: Verilator
    // treats the elements separately, no false loop.
    wire [WIDTH-1:0] g [0:STAGES] /*verilator split_var*/;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [WIDTH-1:0] p [0:STAGES] /*verilator split_var*/;
    /* verilator lint_on UNUSEDSIGNAL */

    // Stage 0: every bit alone; bit 0 includes ci.
    Xor2 #(WIDTH) u_xor2_p(.in1, .in2, .out(p[0]));
    Maj3 u_maj3_g(.in1(in1[0]), .in2(in2[0]), .in3(ci), .out(g[0][0]));
    if (WIDTH > 1) begin : g_wide
        And2 #(WIDTH-1) u_and2_g(.in1(in1[WIDTH-1:1]), .in2(in2[WIDTH-1:1]),
                                 .out(g[0][WIDTH-1:1]));
    end

    // Stages: up the tree with distance 2^s, then down with distance 2^(2*LEVELS-2-s).
    for (genvar s = 0; s < STAGES; s++) begin : g_stage
        localparam UP = s < LEVELS;
        localparam D  = UP ? 1 << s : 1 << (2 * LEVELS - 2 - s);
        for (genvar i = 0; i < WIDTH; i++) begin : g_bit
            if (UP ? (i + 1) % (2 * D) == 0
                   : (i + 1) % (2 * D) == D && i + 1 >= 3 * D) begin : g_combine
                wire pg;    // P_hi & G_lo
                And2 u_and2_0(.in1(p[s][i]), .in2(g[s][i-D]), .out(pg));
                Or2  u_or2   (.in1(g[s][i]), .in2(pg), .out(g[s+1][i]));
                And2 u_and2_1(.in1(p[s][i]), .in2(p[s][i-D]), .out(p[s+1][i]));
            end else begin : g_pass
                assign g[s+1][i] = g[s][i];
                assign p[s+1][i] = p[s][i];
            end
        end
    end

    // Sums: bit i adds the carry out of bits i-1..0 (ci into bit 0).
    Xor2 u_xor2_0(.in1(p[0][0]), .in2(ci), .out(sum[0]));
    if (WIDTH > 1) begin : g_sum
        Xor2 #(WIDTH-1) u_xor2_s(.in1(p[0][WIDTH-1:1]), .in2(g[STAGES][WIDTH-2:0]),
                                 .out(sum[WIDTH-1:1]));
    end
    assign co = g[STAGES][WIDTH-1];

endmodule
