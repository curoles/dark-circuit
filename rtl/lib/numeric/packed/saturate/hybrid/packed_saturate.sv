/* Packed saturation: PackedAdd's sum with every lane that overflowed at the lane's limit,
 * signed or unsigned, and whether some lane did, hybrid.
 *
 * It takes PackedAdd's inputs a, sub, lane and its outputs: the sum, wrapped in every lane,
 * and the flags at every byte's top bit (co, ov), which PackedPkg::lane_broadcast spreads
 * over the lane. A lane overflows: signed, when its signed overflow is set; unsigned, when
 * an addition carries out of it (co 1) or a subtraction borrows (co 0). Its limit: signed,
 * the largest positive or the smallest negative by the sign of the true result, which is a's
 * sign whenever the lane overflows (an addition overflows only when a and b have the same
 * sign, a subtraction only when they differ): with s a's sign, {s, ~s x 7} in the lane's top
 * byte (PackedPkg::lane_tops), ~s x 8 in its other bytes; unsigned, all ones for an
 * addition, 0 for a subtraction. The limits come from inputs, not from the sum, so only the
 * select waits for the adder. sat: some lane overflowed (RISC-V P sets vxsat), the flags at
 * the lanes' top bytes ORed, without the spread. The block always saturates; its user picks
 * result or PackedAdd's sum. WIDTH 32 or 64. Hybrid (AGENTS.md): the select of every byte is
 * a Mux2, the flags and the limits are glue.
 *
 *   a's top bit of every byte, lane --> lane_broadcast --> limit of byte k
 *   co, ov at every byte --> overflow there --> lane_broadcast --> over[k]
 *   sum byte k, limit --> Mux2 (over[k]) --> result byte k
 *   overflow at the lanes' top bytes (lane_tops) --> OR --> sat
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module PackedSaturate import PackedPkg::*; #(
    parameter int WIDTH = 32
)(
    // Only the top bit of every byte is used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire  [WIDTH-1:0]   a,           // PackedAdd's first operand
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire  [WIDTH-1:0]   sum,         // PackedAdd's sum
    input  wire  [WIDTH/8-1:0] co,          // PackedAdd's carry out of every byte's top bit
    input  wire  [WIDTH/8-1:0] ov,          // PackedAdd's signed overflow there
    input  wire                sub,         // PackedAdd's operation: a - b, else a + b
    input  wire                is_unsigned, // unsigned lanes, else signed
    input  lane_e              lane,        // PackedAdd's lane width
    output wire  [WIDTH-1:0]   result,      // sum, every lane that overflowed at its limit
    output wire                sat          // some lane overflowed
);
    localparam int BYTES = WIDTH / 8;

    `DC_STATIC_ASSERT(a_width, WIDTH == 32 || WIDTH == 64)

    logic [BYTES-1:0] sign;     // a's top bit of every byte
    logic [BYTES-1:0] sign_l;   // byte k: a's sign in its lane
    logic [BYTES-1:0] top;      // byte k is its lane's top byte
    logic [BYTES-1:0] flag;     // the overflow at every byte's top bit, if it were a lane's
    logic [BYTES-1:0] over;     // byte k's lane overflowed

    // @kb: rtl/lib/numeric/packed/saturate
    for (genvar k = 0; k < BYTES; k++) begin : g_sign
        assign sign[k] = a[8*k+7];
    end
    assign sign_l = BYTES'(lane_broadcast(8'(sign), lane));
    assign top    = BYTES'(lane_tops(lane));
    assign flag   = is_unsigned ? co ^ {BYTES{sub}} : ov;
    assign over   = BYTES'(lane_broadcast(8'(flag), lane));
    assign sat    = |(flag & top);

    for (genvar k = 0; k < BYTES; k++) begin : g_byte
        logic [7:0] limit;
        assign limit = is_unsigned ? {8{!sub}} : {sign_l[k] ^ !top[k], {7{!sign_l[k]}}};
        Mux2 #(.WIDTH(8)) u_mux2_byte(
            .in0(sum[8*k +: 8]), .in1(limit), .sel(over[k]), .out(result[8*k +: 8]));
    end

endmodule
