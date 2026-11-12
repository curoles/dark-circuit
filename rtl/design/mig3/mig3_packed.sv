/* Mig3 packed unit (P extension, packed SIMD), EX, combinational: the value for rd of a
 * packed instruction, and whether it saturated.
 *
 * The library's packed blocks (rtl/lib/numeric/packed) on rs1 and rs2 as lanes of 8 or 16
 * bits (dec.pk, Mig3Pkg pk_ctrl_t), the operation by dec.pk.op: PK_ADD, PackedAdd's sum,
 * every lane wrapping (PADD, PSUB); PK_SAT, PackedSaturate on it, every lane that
 * overflowed at its limit, signed or unsigned (PSADD, PSADDU, PSSUB, PSSUBU); PK_MIN_MAX,
 * PackedMinMax, the smaller or the larger of rs1 and rs2 by PackedAdd's rs1 - rs2 (PMIN,
 * PMINU, PMAX, PMAXU; decode sets sub); PK_SHIFT, PackedShift, every lane of rs1 shifted by
 * one amount, rs2[4:0] (PSLL.BS, ...) or the immediate (PSLLI.B, ...: its low 3 bits for
 * bytes, 4 for halfwords; the bit above them is part of the encoding). Multiplies come in a
 * later step (rtl/design/mig3/p_profile.md).
 *
 *   rs1, rs2 --> PackedAdd --> sum, co, ov --> PackedSaturate --> saturated, some lane
 *                                   co     --> PackedMinMax   --> min_max
 *   rs1, rs2[4:0] or imm --> PackedShift --> shifted
 *   sum, saturated, min_max, shifted --> select (dec.pk.op) --> result
 *   PK_SAT and some lane --> sat
 *
 * Mig3Core instantiates it in EX, for the instruction in EX; result is rd's value (rd_src
 * RD_PACKED); sat sets vxsat when the instruction completes (Mig3Csr vxsat_set).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig3Packed import Mig3Pkg::*; (
    // Only pk and the low bits of imm are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t dec,       // the instruction taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t    rs1_data,
    input  word_t    rs2_data,
    output word_t    result,
    output logic     sat        // a saturating instruction saturated a lane: sets vxsat
);
    word_t              sum;        // every lane wrapped
    word_t              saturated;  // every lane that overflowed at its limit
    word_t              min_max;    // every lane's minimum or maximum
    word_t              shifted;    // every lane shifted
    logic [WIDTH/8-1:0] co;         // carry and signed overflow at every byte's top bit
    logic [WIDTH/8-1:0] ov;
    logic               some_lane;  // some lane overflowed
    logic [4:0]         amount;     // the shift amount

    // @kb: rtl/design/mig3/packed_unit
    PackedAdd #(.WIDTH(WIDTH)) u_packed_add(
        .a(rs1_data), .b(rs2_data), .sub(dec.pk.sub), .lane(dec.pk.lane), .sum, .co, .ov);

    PackedSaturate #(.WIDTH(WIDTH)) u_packed_saturate(
        .a(rs1_data), .sum, .co, .ov, .sub(dec.pk.sub), .is_unsigned(dec.pk.is_unsigned),
        .lane(dec.pk.lane), .result(saturated), .sat(some_lane));

    PackedMinMax #(.WIDTH(WIDTH)) u_packed_min_max(
        .a(rs1_data), .b(rs2_data), .co, .is_unsigned(dec.pk.is_unsigned), .max(dec.pk.max),
        .lane(dec.pk.lane), .result(min_max));

    assign amount = dec.pk.amt_rs2                   ? rs2_data[4:0] :
                    dec.pk.lane == PackedPkg::LANE_8 ? {2'b00, dec.imm[2:0]} :
                                                       {1'b0, dec.imm[3:0]};

    PackedShift #(.WIDTH(WIDTH)) u_packed_shift(
        .in(rs1_data), .amount, .left(dec.pk.left), .arith(!dec.pk.is_unsigned),
        .lane(dec.pk.lane), .result(shifted));

    always_comb
        case (dec.pk.op)
            PK_SAT:     result = saturated;
            PK_MIN_MAX: result = min_max;
            PK_SHIFT:   result = shifted;
            default:    result = sum;
        endcase

    assign sat = dec.pk.op == PK_SAT && some_lane;

endmodule
