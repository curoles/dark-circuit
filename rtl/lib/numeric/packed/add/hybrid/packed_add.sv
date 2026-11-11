/* Packed add and subtract: a + b or a - b lane by lane, in lanes of 8, 16 or 32 bits that
 * each wrap alone, with the carry and the signed overflow at the top bit of every byte,
 * hybrid.
 *
 * lane (PackedPkg::lane_e) splits the word into lanes; the carry never crosses a lane
 * boundary: a SegmentedKoggeStoneAdder cut at the low bit of every lane
 * (PackedPkg::lane_cuts). sub: a - b = a + ~b + 1 in every lane (b inverted, the carry in 1
 * at every lane's low bit). co[k] is the carry out of byte k's top bit and ov[k] the signed
 * overflow there (the carry into that bit XOR the carry out of it), both within the lane. At
 * a lane's top byte they are the lane's: its carry out (for a subtraction 1 means no borrow,
 * a >= b unsigned) and its signed overflow, what saturation, averaging and compares take
 * (PackedPkg::lane_broadcast spreads them over the lane). WIDTH 32 or 64. Hybrid
 * (AGENTS.md): the adder is the library part; the inversion and the overflow are gates.
 *
 *   a, b ^ sub, ci = sub, cut = lane_cuts(lane) --> SegmentedKoggeStoneAdder --> sum, carry
 *   carry at the top bit of byte k --> co[k]; that carry ^ the carry one bit below --> ov[k]
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module PackedAdd import PackedPkg::*; #(
    parameter int WIDTH = 32
)(
    input  wire  [WIDTH-1:0]   a,
    input  wire  [WIDTH-1:0]   b,
    input  wire                sub,     // a - b, else a + b
    input  lane_e              lane,    // the lane width
    output wire  [WIDTH-1:0]   sum,     // lane by lane, wrapping
    output wire  [WIDTH/8-1:0] co,      // carry out of byte k's top bit, within its lane
    output wire  [WIDTH/8-1:0] ov       // signed overflow at byte k's top bit
);
    localparam int BYTES = WIDTH / 8;

    `DC_STATIC_ASSERT(a_width, WIDTH == 32 || WIDTH == 64)

    wire [WIDTH-1:0] b_in;      // b, inverted for a subtraction
    wire [WIDTH-1:0] cuts;      // the low bits of the lanes
    // The carry out of every bit, within its lane; the top two of each byte are used.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [WIDTH-1:0] carry;
    /* verilator lint_on UNUSEDSIGNAL */

    Xor2 #(WIDTH) u_xor2_sub(.in1(b), .in2({WIDTH{sub}}), .out(b_in));
    assign cuts = WIDTH'(lane_cuts(lane));

    SegmentedKoggeStoneAdder #(.WIDTH(WIDTH)) u_adder(
        .in1(a), .in2(b_in), .ci(sub), .cut(cuts), .carry, .sum);

    for (genvar k = 0; k < BYTES; k++) begin : g_byte
        assign co[k] = carry[8*k+7];
        Xor2 #(1) u_xor2_ov(.in1(carry[8*k+7]), .in2(carry[8*k+6]), .out(ov[k]));
    end

endmodule
