/* Mig3 packed multiply unit (P extension, packed SIMD), EX: the packed multiplies, several
 * cycles, through a result register.
 *
 * The library's PackedMul (rtl/lib/numeric/packed/mul) with one pipeline stage (STAGES 1:
 * 3.4 ns on sky130, kb rtl/lib/numeric/packed/mul) on rs1 and rs2, its mode and the
 * operands' signs from dec.pmul (Mig3Pkg pmul_ctrl_t): the byte products PMUL.H.B00, B01,
 * B11 and their unsigned (PMULU) and signed x unsigned (PMULSU) forms, every 16-bit lane's
 * product of one byte pair, its low 16 bits in the lane. Dot products, the accumulating
 * forms and the high halves come in later steps (rtl/design/mig3/p_profile.md).
 *
 * As Mig3Fpu (kb rtl/design/mig3/fpu): the operation enters in the instruction's first
 * acting cycle, its result comes one clock later and is taken into a register, and the
 * instruction completes in the cycle after, from there: 3 cycles in EX, stall=1 until then.
 * So no multiplier logic is on the path from EX to ID's forwarding, the core's longest.
 * valid is the instruction's cycles in EX that act (not behind a load in MEM/WB, no
 * interrupt taken on it): an interrupt comes before an operation starts, never on one
 * started. hold=1 (a load in MEM/WB waits for its word) keeps a taken result.
 *
 *   rs1_data, rs2_data, dec.pmul --> PackedMul (STAGES 1) --> product, one clock later
 *   lanes' low halves --> result_q (taken once) --> result
 *
 * Mig3Core instantiates it in EX, for the instruction in EX. stall goes to Mig3Control;
 * result is rd's value (rd_src RD_PMUL).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig3PackedMul import Mig3Pkg::*; (
    input  wire      clk,
    input  wire      rst_n,     // synchronous reset, active low
    input  wire      valid,     // the instruction in EX acts (see the header)
    input  wire      hold,      // EX keeps its instruction for another reason
    // Only pmul is used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t dec,       // the instruction taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t    rs1_data,
    input  word_t    rs2_data,
    output wire      stall,     // the result of the instruction in EX is not there yet
    output word_t    result
);
    logic pm;           // a packed multiply that acts
    logic start;        // its operation enters PackedMul
    logic busy;         // the operation is in PackedMul
    logic out_valid;    // PackedMul's result is the operation's
    logic ready;        // the result is in result_q: the instruction completes
    logic take;         // PackedMul's result is there: into result_q now

    assign pm    = valid && dec.pmul.en;
    assign start = pm && !busy && !ready;

    // The lanes' 32-bit products; their low halves are the byte products. The dot products
    // and the high halves are not used yet.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [2*WIDTH-1:0] product;
    word_t              dot;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/design/mig3/packed_mul
    PackedMul #(.WIDTH(WIDTH), .STAGES(1)) u_packed_mul(
        .clk, .rst_n, .in_valid(start), .a(rs1_data), .b(rs2_data),
        .a_signed(dec.pmul.a_signed), .b_signed(dec.pmul.b_signed), .mode(dec.pmul.mode),
        .acc('0), .acc_en(1'b0), .product, .dot, .out_valid);

    always_ff @(posedge clk)
        if (!rst_n) busy <= 1'b0;
        else        busy <= start || (busy && !out_valid);

    // Every lane's 16-bit byte product: the low half of its 32-bit product.
    word_t unit_result;
    for (genvar k = 0; k < WIDTH / 16; k++) begin : g_lane
        assign unit_result[16*k +: 16] = product[32*k +: 16];
    end

    // The result register: taken once per instruction, kept while EX holds.
    word_t result_q;

    assign take = pm && out_valid && !ready;

    always_ff @(posedge clk)
        if (!rst_n) ready <= 1'b0;
        else        ready <= take || (ready && hold);

    always_ff @(posedge clk)
        if (take) result_q <= unit_result;

    assign stall  = pm && !ready;
    assign result = result_q;

    // An operation runs only while its instruction is in EX: nothing removes a packed
    // multiply from EX before its result (an interrupt comes before it starts).
    `DC_ASSERT(a_busy_has_pmul, !busy || dec.pmul.en)
    // The instruction and its registers do not change while it waits for its result.
    `DC_ASSERT_NEXT(a_inputs_held, stall,
                    $stable(rs1_data) && $stable(rs2_data) && $stable(dec.pmul))

endmodule
