/* Segmented Kogge-Stone adder: sum = in1 + in2 + ci in every segment, the carry chain cut
 * at the bits cut marks, parallel prefix, made of gates.
 *
 * KoggeStoneAdder (see there) with segments: cut[i] = 1 makes bit i the low bit of a
 * segment, which takes ci as its carry in, as bit 0 does (bit 0 always starts one: cut[0]
 * is not used). Such a bit's generate includes ci (Maj3) and its propagate into the prefix
 * is 0, so no carry from below crosses into the segment, and its sum adds ci. carry[i] is
 * the carry out of bit i within its segment: at a segment's top bit the segment's carry
 * out, one bit below it the carry into the top bit (their XOR is the signed overflow).
 * Packed SIMD cuts at lane boundaries (PackedAdd). One select more than KoggeStoneAdder at
 * every bit that may start a segment, in the first level and in the sum; the same
 * log2(WIDTH) levels of combines. A cut that is a constant 0 folds away in synthesis.
 *
 *   in1, in2 --> p = in1 ^ in2, g = start ? Maj3(in1, in2, ci) : in1 & in2,
 *                p into the prefix = p & ~start
 *            --> log2(WIDTH) levels: G = G_hi | P_hi & G_lo, P = P_hi & P_lo --> carry
 *   sum[i] = p[i] ^ (start[i] ? ci : carry[i-1])
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module SegmentedKoggeStoneAdder #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire             ci,     // carry in of every segment
    // cut[0] is not used: bit 0 always starts a segment.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [WIDTH-1:0] cut,    // cut[i]: bit i is the low bit of a segment
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [WIDTH-1:0] carry,  // carry out of each bit, within its segment
    output wire [WIDTH-1:0] sum
);
    localparam LEVELS = $clog2(WIDTH);

    wire [WIDTH-1:0] start;     // bit i starts a segment
    wire [WIDTH-1:0] p_bit;     // in1 ^ in2
    wire [WIDTH-1:0] g_and;     // in1 & in2: the generate of a bit inside a segment
    wire [WIDTH-1:0] g_maj;     // Maj3(in1, in2, ci): the generate of a segment's low bit
    wire [WIDTH-1:0] not_start;
    wire [WIDTH-1:0] cin;       // carry into each bit

    // g[l][i], p[l][i]: generate and propagate of the span of bits i down to i - 2^l + 1,
    // stopped at the segment's low bit (its propagate is 0). split_var: Verilator treats
    // the elements separately, no false loop.
    wire [WIDTH-1:0] g [0:LEVELS] /*verilator split_var*/;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [WIDTH-1:0] p [0:LEVELS] /*verilator split_var*/;
    /* verilator lint_on UNUSEDSIGNAL */

    assign start = {cut[WIDTH-1:1], 1'b1};

    // Level 0: every bit alone; a segment's low bit includes ci and passes no propagate.
    Xor2 #(WIDTH) u_xor2_p(.in1, .in2, .out(p_bit));
    And2 #(WIDTH) u_and2_g(.in1, .in2, .out(g_and));
    Maj3 #(WIDTH) u_maj3_g(.in1, .in2, .in3({WIDTH{ci}}), .out(g_maj));
    Inv  #(WIDTH) u_inv_start(.in(start), .out(not_start));
    And2 #(WIDTH) u_and2_p(.in1(p_bit), .in2(not_start), .out(p[0]));
    for (genvar i = 0; i < WIDTH; i++) begin : g_level0
        Mux2 #(1) u_mux2_g(.in0(g_and[i]), .in1(g_maj[i]), .sel(start[i]), .out(g[0][i]));
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
    assign carry = g[LEVELS];

    // Sums: bit i adds ci when it starts a segment, else the carry out of the bit below.
    assign cin[0] = ci;
    for (genvar i = 1; i < WIDTH; i++) begin : g_cin
        Mux2 #(1) u_mux2_cin(.in0(carry[i-1]), .in1(ci), .sel(start[i]), .out(cin[i]));
    end
    Xor2 #(WIDTH) u_xor2_s(.in1(p_bit), .in2(cin), .out(sum));

endmodule
