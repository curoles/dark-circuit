/* Mig3 floating-point unit (Zfinx: F on the x registers), EX.
 *
 * The library's fp32 blocks (rtl/lib/numeric/fp32), one per kind of F instruction
 * (dec.fp.unit, Mig3Pkg fp_unit_e): Fp32Fma (FMADD.S, FMSUB.S, FNMSUB.S, FNMADD.S with
 * rs3 the addend; FADD.S, FSUB.S, FMUL.S), Fp32DivSqrt, Fp32Compare, Fp32MinMax,
 * Fp32SignInject, Fp32Class, Fp32ToInt, Fp32FromInt, with RISC-V's rules where ISAs
 * differ (minimumNumber/maximumNumber, the invalid conversion's integer).
 *
 * Every result comes from a register: the unit's result and flags are taken into it, and
 * the instruction completes in the cycle after, from there. So no fp32 block is on the
 * path from EX to ID's forwarding, the core's longest (kb rtl/design/mig3/fpu), and
 * stall=1 holds the instruction in EX until then:
 *  - Fp32Compare, Fp32MinMax, Fp32SignInject, Fp32Class, Fp32ToInt, Fp32FromInt are
 *    combinational: taken in the first cycle, 2 cycles in EX;
 *  - Fp32Fma with FMA_STAGES pipeline stages: the operation enters in the first cycle, its
 *    result comes FMA_STAGES cycles later and is taken then: 2 + FMA_STAGES cycles; an
 *    R4 instruction (FMADD.S ...) first takes rs3 (rs3_read: Mig3Core lends it ID's rs2
 *    port, rs3_data) into a register and enters the cycle after: 3 + FMA_STAGES;
 *  - Fp32DivSqrt starts in the first cycle and runs its 25 clocks (Divider handshake): its
 *    result is taken in the cycle after done, 27 cycles.
 * valid is the instruction's cycles in EX that act (not behind a load in MEM/WB, no
 * interrupt taken on it): an interrupt comes before an F instruction starts, never on one
 * started. hold=1 (a load in MEM/WB waits for its word) keeps a taken result, as in
 * Mig3MulDiv.
 *
 * The rounding mode: the instruction's rm field, or frm for FRM_DYN (Mig3Csr); illegal=1
 * when the instruction rounds and frm's mode is not one (101, 110, 111): it traps (the rm
 * field's reserved values are illegal at decode already, kb rtl/design/mig3/fp_decode).
 * flags (NV DZ OF UF NX, fflags' order) go with the result; Mig3Csr ORs them into fflags
 * when the instruction completes.
 *
 *   rs3_data --> rs3_q (an R4's first cycle) -+
 *   rs1_data, rs2_data, dec.fp, rm --> Fp32Fma (FMA_STAGES) ------+
 *                                  --> Fp32DivSqrt (25 clocks) ---+--> unit's result, flags
 *                                  --> compare, min/max, sgnj,  --+       |  taken
 *                                      class, to int, from int            v
 *                                                              result_q, flags_q --> result
 *
 * Mig3Core instantiates it in EX, for the instruction in EX. stall and illegal go to
 * Mig3Control; result is rd's value (rd_src RD_FP), flags go to Mig3Csr.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig3Fpu import Mig3Pkg::*, Fp32Pkg::*, FpPkg::*; (
    input  wire               clk,
    input  wire               rst_n,    // synchronous reset, active low
    input  wire               valid,    // the instruction in EX acts (see the header)
    input  wire               hold,     // EX keeps its instruction for another reason
    // Only fp and uses_rs3 are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t          dec,      // the instruction taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t             rs1_data,
    input  word_t             rs2_data,
    input  word_t             rs3_data, // R4: rs3 through ID's rs2 port, while rs3_read
    input  RiscvPkg::funct3_t frm,      // fcsr.frm, the mode of FRM_DYN
    output wire               illegal,  // the F instruction can not be done (not valid-gated)
    output wire               rs3_read, // an R4 wants rs3 now, from flops (not valid-gated)
    output wire               stall,    // the result of the instruction in EX is not there yet
    output word_t             result,
    output flags_t            flags
);
    // @kb: rtl/design/mig3/fpu
    // Fp32Fma's stages: 5.1 ns on sky130 with 3, under Mig3's clock (kb
    // rtl/lib/numeric/fp32/fma_stages).
    localparam int FMA_STAGES = 3;

    // The rounding mode. The rm field's values are FpPkg::rm_e's (RiscvPkg FRM_DYN).
    RiscvPkg::funct3_t rm_field;    // the instruction's, or frm's for FRM_DYN
    rm_e               rm;

    assign rm_field = dec.fp.rm == RiscvPkg::FRM_DYN ? frm : dec.fp.rm;
    assign rm       = rm_e'(rm_field);
    assign illegal  = dec.fp.en && dec.fp.uses_rm &&
                      (RiscvPkg::rm_reserved(rm_field) || rm_field == RiscvPkg::FRM_DYN);

    // The instruction in EX, by unit.
    logic   fp;             // an F instruction that acts and can be done
    logic   fma;
    logic   div_sqrt;
    logic   ready;          // its result is in result_q: it completes
    logic   take;           // the unit's result is there: into result_q now

    assign fp       = valid && dec.fp.en && !illegal;
    assign fma      = fp && dec.fp.unit == FPU_FMA;
    assign div_sqrt = fp && dec.fp.unit == FPU_DIV_SQRT;

    // Fp32Fma: the operation enters once, its result comes FMA_STAGES clocks later.
    logic   fma_start;
    logic   fma_busy;       // the operation is in the pipeline
    logic   fma_out_valid;
    fp32_t  fma_result;
    flags_t fma_flags;

    // rs3 of an R4 instruction: taken in its first acting cycle (Mig3Core lends ID's rs2
    // port while rs3_read), kept until it leaves; the operation enters the cycle after.
    // @kb: rtl/design/mig3/rs3_read
    logic   rs3_take;
    logic   rs3_got;        // rs3_q holds rs3 of the R4 in EX
    word_t  rs3_q;

    assign rs3_read = dec.fp.en && dec.uses_rs3 && !rs3_got;
    assign rs3_take = fp && dec.uses_rs3 && !rs3_got;

    always_ff @(posedge clk)
        if (!rst_n) rs3_got <= 1'b0;
        else        rs3_got <= (rs3_take || rs3_got) && !(ready && !hold);

    always_ff @(posedge clk)
        if (rs3_take) rs3_q <= rs3_data;

    assign fma_start = fma && !fma_busy && !ready && (!dec.uses_rs3 || rs3_got);

    // ADD, SUB and MUL do not use c.
    Fp32Fma #(.STAGES(FMA_STAGES)) u_fma(
        .clk, .rst_n, .in_valid(fma_start), .a(rs1_data), .b(rs2_data), .c(rs3_q),
        .op(dec.fp.fma_op), .rm, .out_valid(fma_out_valid), .result(fma_result),
        .flags(fma_flags));

    always_ff @(posedge clk)
        if (!rst_n) fma_busy <= 1'b0;
        else        fma_busy <= fma_start || (fma_busy && !fma_out_valid);

    // Fp32DivSqrt: starts once; its result is there in the cycle after done.
    logic   ds_start;
    logic   ds_busy;
    logic   ds_done;
    logic   ds_after;       // the cycle after done
    fp32_t  ds_result;
    flags_t ds_flags;

    assign ds_start = div_sqrt && !ds_busy && !ds_after && !ready;

    Fp32DivSqrt u_div_sqrt(
        .clk, .rst_n, .start(ds_start), .sqrt(dec.fp.sqrt), .a(rs1_data), .b(rs2_data), .rm,
        .busy(ds_busy), .done(ds_done), .result(ds_result), .flags(ds_flags));

    always_ff @(posedge clk)
        if (!rst_n) ds_after <= 1'b0;
        else        ds_after <= ds_done;

    // The combinational units.
    logic   cmp_eq;
    logic   cmp_lt;
    logic   cmp_le;
    logic   cmp_unordered;
    logic   cmp_snan;
    fp32_t  min_max;
    logic   min_max_nv;
    fp32_t  sgnj;
    class_t fclass;
    word_t  to_int;
    flags_t to_int_flags;
    fp32_t  from_int;
    flags_t from_int_flags;

    Fp32Compare u_compare(
        .a(rs1_data), .b(rs2_data), .eq(cmp_eq), .lt(cmp_lt), .le(cmp_le),
        .unordered(cmp_unordered), .snan(cmp_snan));
    Fp32MinMax #(.NAN_RULE(MINMAX_NUMBER)) u_min_max(
        .a(rs1_data), .b(rs2_data), .max(dec.fp.max), .result(min_max), .nv(min_max_nv));
    Fp32SignInject u_sign_inject(.a(rs1_data), .b(rs2_data), .op(dec.fp.sgnj), .result(sgnj));
    Fp32Class u_class(.x(rs1_data), .c(fclass));
    Fp32ToInt #(.INVALID(TOINT_RISCV)) u_to_int(
        .x(rs1_data), .is_signed(!dec.fp.is_unsigned), .rm, .result(to_int),
        .flags(to_int_flags));
    Fp32FromInt u_from_int(
        .a(rs1_data), .is_signed(!dec.fp.is_unsigned), .rm, .result(from_int),
        .flags(from_int_flags));

    // The unit's result and flags; FEQ.S is a quiet compare (NV for a signalling NaN), FLT.S
    // and FLE.S signal (NV for any NaN).
    word_t  unit_result;
    flags_t unit_flags;
    logic   unit_ready;     // the unit's result is there in this cycle

    always_comb begin
        unit_flags = '0;
        unit_ready = fp;
        case (dec.fp.unit)
            FPU_FMA: begin
                unit_result = fma_result;
                unit_flags  = fma_flags;
                unit_ready  = fma && fma_out_valid;
            end
            FPU_DIV_SQRT: begin
                unit_result = ds_result;
                unit_flags  = ds_flags;
                unit_ready  = div_sqrt && ds_after;
            end
            FPU_CMP: begin
                case (dec.fp.cmp)
                    FP_CMP_EQ: unit_result = word_t'(cmp_eq);
                    FP_CMP_LT: unit_result = word_t'(cmp_lt);
                    default:   unit_result = word_t'(cmp_le);
                endcase
                unit_flags.nv = dec.fp.cmp == FP_CMP_EQ ? cmp_snan : cmp_unordered;
            end
            FPU_MIN_MAX: begin
                unit_result   = min_max;
                unit_flags.nv = min_max_nv;
            end
            FPU_SGNJ:     unit_result = sgnj;
            FPU_CLASS:    unit_result = word_t'(fclass);
            FPU_TO_INT: begin
                unit_result = to_int;
                unit_flags  = to_int_flags;
            end
            default: begin  // FPU_FROM_INT
                unit_result = from_int;
                unit_flags  = from_int_flags;
            end
        endcase
    end

    // The result register: taken once per instruction, kept while EX holds.
    word_t  result_q;
    flags_t flags_q;

    assign take = unit_ready && !ready;

    always_ff @(posedge clk)
        if (!rst_n) ready <= 1'b0;
        else        ready <= take || (ready && hold);

    always_ff @(posedge clk)
        if (take) begin
            result_q <= unit_result;
            flags_q  <= unit_flags;
        end

    assign stall  = fp && !ready;
    assign result = result_q;
    assign flags  = flags_q;

    // An operation runs only while its instruction is in EX: nothing removes an F
    // instruction from EX before its result (an interrupt comes before it starts).
    `DC_ASSERT(a_fma_busy_has_fma, !fma_busy || (dec.fp.en && dec.fp.unit == FPU_FMA))
    `DC_ASSERT(a_ds_busy_has_ds, !ds_busy || (dec.fp.en && dec.fp.unit == FPU_DIV_SQRT))
    // rs3 is taken before the operation enters, and the operation only with it.
    `DC_ASSERT(a_fma_has_rs3, !fma_start || !dec.uses_rs3 || rs3_got)
    // The instruction and its registers do not change while it waits for its result.
    `DC_ASSERT_NEXT(a_inputs_held, stall,
                    $stable(rs1_data) && $stable(rs2_data) && $stable(dec.fp))

endmodule
