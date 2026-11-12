/* Packed minimum and maximum: the smaller or the larger of a and b in every lane, signed or
 * unsigned, from PackedAdd's a - b, hybrid.
 *
 * It takes PackedAdd's carries for a - b (sub 1) in the same lanes: a lane's carry out (co
 * at its top byte) is 1 when a >= b unsigned, so a < b unsigned is no carry out. Signed, a
 * < b is the same when a and b have the same sign, and a's sign (a negative) when their
 * signs differ. The compare needs only the carry and the operands' signs, not the sum (its
 * latest bit) nor the signed overflow; PackedPkg::lane_broadcast spreads it over the lane.
 * The minimum is a when a < b, else b; the maximum is b when a < b, else a; equal lanes are
 * the same either way. WIDTH 32 or 64. Hybrid (AGENTS.md): the select of every byte is a
 * Mux2, the compare is glue.
 *
 *   a, b top bit of every byte, co --> a < b at every byte --> lane_broadcast --> lt[k]
 *   a byte k, b byte k --> Mux2 (lt[k] for max, !lt[k] for min) --> result byte k
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module PackedMinMax import PackedPkg::*; #(
    parameter int WIDTH = 32
)(
    input  wire  [WIDTH-1:0]   a,
    input  wire  [WIDTH-1:0]   b,
    input  wire  [WIDTH/8-1:0] co,          // PackedAdd's carry out at every byte, a - b
    input  wire                is_unsigned, // unsigned lanes, else signed
    input  wire                max,         // the larger, else the smaller
    input  lane_e              lane,        // PackedAdd's lane width
    output wire  [WIDTH-1:0]   result       // every lane's minimum or maximum
);
    localparam int BYTES = WIDTH / 8;

    `DC_STATIC_ASSERT(a_width, WIDTH == 32 || WIDTH == 64)

    logic [BYTES-1:0] sa;       // a's top bit of every byte
    logic [BYTES-1:0] sb;       // b's
    logic [BYTES-1:0] less;     // a < b at every byte's top bit, if it were a lane's
    logic [BYTES-1:0] lt;       // byte k: a < b in its lane
    logic [BYTES-1:0] pick_b;   // byte k: the result is b's

    // @kb: rtl/lib/numeric/packed/min_max
    for (genvar k = 0; k < BYTES; k++) begin : g_sign
        assign sa[k] = a[8*k+7];
        assign sb[k] = b[8*k+7];
    end
    for (genvar k = 0; k < BYTES; k++) begin : g_less
        assign less[k] = (!is_unsigned && sa[k] != sb[k]) ? sa[k] : !co[k];
    end
    assign lt     = BYTES'(lane_broadcast(8'(less), lane));
    assign pick_b = max ? lt : ~lt;

    for (genvar k = 0; k < BYTES; k++) begin : g_byte
        Mux2 #(.WIDTH(8)) u_mux2_byte(
            .in0(a[8*k +: 8]), .in1(b[8*k +: 8]), .sel(pick_b[k]), .out(result[8*k +: 8]));
    end

endmodule
