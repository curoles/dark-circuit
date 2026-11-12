/* Packed shift: every lane of in shifted by the same amount, left or right, logical or
 * arithmetic, hybrid.
 *
 * Lanes of 8, 16 or 32 bits (PackedPkg::lane_e); amount 0 to 31, the same for every lane
 * (RISC-V P: rs2[4:0] or an immediate). A lane shifted by its width or more is all fill: 0,
 * or for an arithmetic right shift its sign. Because every lane moves by the same amount,
 * one shifter of the whole word does it: a lane's bits that cross into the next lane land
 * exactly on the bits the shift vacated there, and a keep mask clears them (per lane: the
 * bits at offset >= amount for a left shift, at offset + amount < width for a right shift,
 * none when amount >= width). The vacated bits take the fill: the lane's sign (its top bit,
 * spread by PackedPkg::lane_broadcast) for an arithmetic right shift, else 0. The mask
 * depends on amount, left and lane only, so it is made beside the shifter, not after it.
 * WIDTH 32 or 64. Hybrid (AGENTS.md): the word shift is a BarrelShifter, the masks are glue.
 *
 *   in, amount, left --> BarrelShifter (logical) --> shifted
 *   amount, left, lane --> keep
 *   result = (shifted & keep) | (~keep & fill)
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module PackedShift import PackedPkg::*; #(
    parameter int WIDTH = 32
)(
    input  wire  [WIDTH-1:0] in,
    input  wire  [4:0]       amount,    // positions, the same for every lane
    input  wire              left,      // left, else right
    input  wire              arith,     // a right shift fills with the lane's sign, else 0
    input  lane_e            lane,      // the lane width
    output wire  [WIDTH-1:0] result
);
    localparam int BYTES       = WIDTH / 8;
    localparam int SHIFT_WIDTH = $clog2(WIDTH);

    `DC_STATIC_ASSERT(a_width, WIDTH == 32 || WIDTH == 64)

    // The bits that stay in their lane of lb bits after the shift.
    function automatic logic [WIDTH-1:0] keep_of(int lb, logic [4:0] s, logic l);
        logic [WIDTH-1:0] k;
        for (int j = 0; j < WIDTH; j++)
            k[j] = l ? (j % lb >= int'(s)) : (j % lb + int'(s) < lb);
        return k;
    endfunction

    logic [WIDTH-1:0] shifted;  // the whole word shifted
    logic [WIDTH-1:0] keep;     // bits that stay in their lane
    logic [BYTES-1:0] sign;     // in's top bit of every byte
    logic [BYTES-1:0] sign_l;   // byte k: the sign of its lane
    logic [WIDTH-1:0] fill;     // the vacated bits' value

    BarrelShifter #(.WIDTH(WIDTH)) u_barrel_shifter(
        .in, .shift_in_bit(1'b0), .shift(SHIFT_WIDTH'(amount)), .shift_rotate(1'b1),
        .left_right(left), .out(shifted));

    // @kb: rtl/lib/numeric/packed/shift
    always_comb
        case (lane)
            LANE_8:  keep = keep_of(8, amount, left);
            LANE_16: keep = keep_of(16, amount, left);
            default: keep = keep_of(32, amount, left);
        endcase

    for (genvar k = 0; k < BYTES; k++) begin : g_sign
        assign sign[k] = in[8*k+7];
        assign fill[8*k +: 8] = {8{sign_l[k] && arith && !left}};
    end
    assign sign_l = BYTES'(lane_broadcast(8'(sign), lane));
    assign result = (shifted & keep) | (~keep & fill);

endmodule
