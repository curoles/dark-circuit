/* Mig3 packed multiply unit (P extension, packed SIMD), EX: the packed multiplies, several
 * cycles, through a result register.
 *
 * The library's PackedMul (rtl/lib/numeric/packed/mul) with one pipeline stage (STAGES 1:
 * 3.4 ns on sky130, kb rtl/lib/numeric/packed/mul) on rs1 and rs2, its mode and the
 * operands' signs from dec.pmul (Mig3Pkg pmul_ctrl_t): the byte products PMUL.H.B00, B01,
 * B11 and their unsigned (PMULU) and signed x unsigned (PMULSU) forms, every 16-bit lane's
 * product of one byte pair, its low 16 bits in the lane; the dot products PM4ADD.B (four
 * byte products summed) and PM2ADD.H (two halfword products) with their PMxADDU and
 * PMxADDSU forms, every 32-bit group's sum; the accumulating forms PM4ADDA.B, PM2ADDA.H and
 * theirs, rd plus the sum; the high halves PMULH.H, PMULHU.H, PMULHSU.H and, rounded (2^15
 * added), PMULHR.H and theirs, every lane's bits 31..16; the Q15 products PMULQ.H and,
 * rounded (2^14 added), PMULQR.H, every lane's bits 30..15, 0x7fff when both operands are
 * 0x8000 (the one product that does not fit), which sets vxsat (sat, when the instruction
 * completes). dec.pmul.res picks the result, dec.pmul.round PackedMul's rounding.
 *
 * As Mig3Fpu (kb rtl/design/mig3/fpu): the operation enters in the instruction's first
 * acting cycle, its result comes one clock later and is taken into a register, and the
 * instruction completes in the cycle after, from there: 3 cycles in EX, stall=1 until then.
 * So no multiplier logic is on the path from EX to ID's forwarding, the core's longest. An
 * accumulating form first takes rd, as an R4 instruction takes rs3 (rs3_read: Mig3Core
 * lends it ID's rs2 port, rs3_data, decode giving rs3 = rd), into a register, and enters the
 * cycle after: 4 cycles. valid is the instruction's cycles in EX that act (not behind a load
 * in MEM/WB, no interrupt taken on it): an interrupt comes before an operation starts,
 * never on one started. hold=1 (a load in MEM/WB waits for its word) keeps a taken result.
 *
 *   rs3_data --> acc_q (an accumulating form's first cycle) -------+
 *   rs1_data, rs2_data, dec.pmul --> PackedMul (STAGES 1) <---------+ acc
 *                                    --> product, dot, one clock later
 *   by dec.pmul.res: lanes' low or high halves, Q15, dot --> result_q, sat_q (taken once)
 *
 * Mig3Core instantiates it in EX, for the instruction in EX. stall goes to Mig3Control;
 * result is rd's value (rd_src RD_PMUL); sat goes to Mig3Csr (vxsat_set).
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
    input  word_t    rs3_data,  // accumulating forms: rd through ID's rs2 port, while rs3_read
    output wire      rs3_read,  // an accumulating form wants rd now, from flops (not valid-gated)
    output wire      stall,     // the result of the instruction in EX is not there yet
    output word_t    result,
    output wire      sat        // a Q15 lane saturated: sets vxsat when the insn completes
);
    logic pm;           // a packed multiply that acts
    logic start;        // its operation enters PackedMul
    logic busy;         // the operation is in PackedMul
    logic out_valid;    // PackedMul's result is the operation's
    logic ready;        // the result is in result_q: the instruction completes
    logic take;         // PackedMul's result is there: into result_q now

    assign pm = valid && dec.pmul.en;

    // The accumulator of an accumulating form: rd, taken in its first acting cycle (Mig3Core
    // lends ID's rs2 port while rs3_read), kept until it leaves; the operation enters the
    // cycle after.
    // @kb: rtl/design/mig3/rs3_read
    logic  acc_take;
    logic  acc_got;     // acc_q holds rd of the accumulating form in EX
    word_t acc_q;

    assign rs3_read = dec.pmul.en && dec.pmul.acc && !acc_got;
    assign acc_take = pm && dec.pmul.acc && !acc_got;

    always_ff @(posedge clk)
        if (!rst_n) acc_got <= 1'b0;
        else        acc_got <= (acc_take || acc_got) && !(ready && !hold);

    always_ff @(posedge clk)
        if (acc_take) acc_q <= rs3_data;

    assign start = pm && !busy && !ready && (!dec.pmul.acc || acc_got);

    logic [2*WIDTH-1:0] product;    // the lanes' 32-bit products
    word_t              dot;        // the dot products of the 32-bit groups

    // @kb: rtl/design/mig3/packed_mul
    PackedMul #(.WIDTH(WIDTH), .STAGES(1)) u_packed_mul(
        .clk, .rst_n, .in_valid(start), .a(rs1_data), .b(rs2_data),
        .a_signed(dec.pmul.a_signed), .b_signed(dec.pmul.b_signed), .mode(dec.pmul.mode),
        .acc(acc_q), .acc_en(dec.pmul.acc), .round_en(dec.pmul.round),
        .round_pos(dec.pmul.res == PMR_Q15 ? 5'd14 : 5'd15), .product, .dot, .out_valid);

    always_ff @(posedge clk)
        if (!rst_n) busy <= 1'b0;
        else        busy <= start || (busy && !out_valid);

    // The results by kind (dec.pmul.res): every lane's low half (the byte products), high
    // half (PMULH, PMULHR) or bits 30..15 (Q15: PMULQ, PMULQR; 0x7fff for 0x8000 * 0x8000,
    // the one product that does not fit, which saturates), or the dot products.
    word_t               low_halves;
    word_t               high_halves;
    word_t               q15;
    logic [WIDTH/16-1:0] q15_sat;     // a lane's operands both 0x8000
    word_t               unit_result;
    logic                unit_sat;    // a Q15 lane saturated
    for (genvar k = 0; k < WIDTH / 16; k++) begin : g_lane
        assign low_halves[16*k +: 16]  = product[32*k +: 16];
        assign high_halves[16*k +: 16] = product[32*k + 16 +: 16];
        assign q15_sat[k] = rs1_data[16*k +: 16] == 16'h8000 &&
                            rs2_data[16*k +: 16] == 16'h8000;
        assign q15[16*k +: 16] = q15_sat[k] ? 16'h7fff : product[32*k + 15 +: 16];
    end
    always_comb
        case (dec.pmul.res)
            PMR_DOT:  unit_result = dot;
            PMR_HIGH: unit_result = high_halves;
            PMR_Q15:  unit_result = q15;
            default:  unit_result = low_halves;
        endcase
    assign unit_sat = dec.pmul.res == PMR_Q15 && |q15_sat;

    // The result register: taken once per instruction, kept while EX holds.
    word_t result_q;
    logic  sat_q;       // the result saturated a lane (Q15)

    assign take = pm && out_valid && !ready;

    always_ff @(posedge clk)
        if (!rst_n) ready <= 1'b0;
        else        ready <= take || (ready && hold);

    always_ff @(posedge clk)
        if (take) begin
            result_q <= unit_result;
            sat_q    <= unit_sat;
        end

    assign stall  = pm && !ready;
    assign result = result_q;
    assign sat    = ready && sat_q;

    // An operation runs only while its instruction is in EX: nothing removes a packed
    // multiply from EX before its result (an interrupt comes before it starts).
    `DC_ASSERT(a_busy_has_pmul, !busy || dec.pmul.en)
    // The accumulator is taken before the operation enters, and the operation only with it.
    `DC_ASSERT(a_start_has_acc, !start || !dec.pmul.acc || acc_got)
    // The instruction and its registers do not change while it waits for its result.
    `DC_ASSERT_NEXT(a_inputs_held, stall,
                    $stable(rs1_data) && $stable(rs2_data) && $stable(dec.pmul))

endmodule
