/* One-operand bit manipulations, made of blocks and gates, combinational: out = op(in). They
 * are the Zbb SEXT.B, SEXT.H, ZEXT.H, ORC.B, REV8, CLZ, CTZ, CPOP; the two-operand Zbb
 * (ANDN, MIN, ROL, ...) are not here, they reuse an ALU's adder, logic and shifter.
 * WIDTH is a power of 2, 16 or more. CLZ and CTZ of 0 are WIDTH.
 *
 * Same ports and result as the behave version. SEXT.B, SEXT.H, ZEXT.H and REV8 are wiring;
 * ORC.B is an OrReduce per byte. CLZ and CTZ share one PriorityEncoder: for CTZ it gets the
 * operand bit-reversed (wiring and a Mux2), so that its lowest one becomes the highest. With
 * the index h of the highest one, the count is WIDTH-1-h = ~h; with no one it is WIDTH:
 * {~valid, ~h & valid}. CPOP is a PopCount. A Mux8 selects the result by op.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module ComputeCoreBitmanip import ComputeCoreBitmanipPkg::*; #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] in,
    input  bm_op_e          op,
    output wire [WIDTH-1:0] out
);
    // @kb: rtl/lib/block/compute_core_bitmanip/library_block
    `DC_STATIC_ASSERT(a_width_power_of_2, WIDTH >= 16 && (WIDTH & (WIDTH - 1)) == 0)

    localparam SIZE  = $clog2(WIDTH);       // bits of a bit index
    localparam CW    = SIZE + 1;            // bits of a count 0..WIDTH
    localparam BYTES = WIDTH / 8;

    wire [WIDTH-1:0] result [8];    // result[o]: the result of operation o
    wire [BYTES-1:0] byte_set;      // ORC.B: byte k is not 0
    wire [WIDTH-1:0] reversed;      // in with its bits in reverse order
    wire             is_ctz;
    wire [WIDTH-1:0] pe_in;         // in for CLZ, reversed for CTZ
    wire [SIZE-1:0]  pe_out;        // index of the highest one of pe_in
    wire             pe_valid;      // pe_in is not 0
    wire [SIZE-1:0]  pe_out_n;
    wire [SIZE-1:0]  zeros_low;     // the count when pe_in is not 0: ~pe_out
    wire             pe_none;       // pe_in is 0: the count is WIDTH
    wire [CW-1:0]    zeros;         // CLZ or CTZ
    wire [CW-1:0]    ones;          // CPOP

    assign result[BM_SEXT_B] = {{(WIDTH - 8){in[7]}}, in[7:0]};
    assign result[BM_SEXT_H] = {{(WIDTH - 16){in[15]}}, in[15:0]};
    assign result[BM_ZEXT_H] = {{(WIDTH - 16){1'b0}}, in[15:0]};

    for (genvar k = 0; k < BYTES; k++) begin : g_byte
        OrReduce #(8) u_or_reduce(.in(in[8*k +: 8]), .out(byte_set[k]));
        assign result[BM_ORC_B][8*k +: 8] = {8{byte_set[k]}};
        assign result[BM_REV8][8*k +: 8]  = in[WIDTH-8-8*k +: 8];
    end

    for (genvar k = 0; k < WIDTH; k++) begin : g_reverse
        assign reversed[k] = in[WIDTH-1-k];
    end

    // The package name is needed: Icarus takes an imported name alone as a port expression
    // for an implicit wire.
    CmpEq #(3) u_cmp_eq_ctz(.in1(op), .in2(ComputeCoreBitmanipPkg::BM_CTZ), .eq(is_ctz));
    Mux2 #(WIDTH) u_mux2_pe_in(.in0(in), .in1(reversed), .sel(is_ctz), .out(pe_in));
    PriorityEncoder #(.SIZE(SIZE)) u_priority_encoder(
        .in(pe_in), .out(pe_out), .valid(pe_valid));
    Inv #(SIZE) u_inv_pe_out(.in(pe_out), .out(pe_out_n));
    And2 #(SIZE) u_and2_zeros(.in1(pe_out_n), .in2({SIZE{pe_valid}}), .out(zeros_low));
    Inv u_inv_pe_valid(.in(pe_valid), .out(pe_none));
    assign zeros = {pe_none, zeros_low};

    PopCount #(.WIDTH(WIDTH)) u_pop_count(.in, .count(ones));

    assign result[BM_CLZ]  = {{(WIDTH - CW){1'b0}}, zeros};
    assign result[BM_CTZ]  = {{(WIDTH - CW){1'b0}}, zeros};
    assign result[BM_CPOP] = {{(WIDTH - CW){1'b0}}, ones};

    Mux8 #(WIDTH) u_mux8_out(
        .in0(result[0]), .in1(result[1]), .in2(result[2]), .in3(result[3]),
        .in4(result[4]), .in5(result[5]), .in6(result[6]), .in7(result[7]),
        .sel(op), .out(out));

endmodule
