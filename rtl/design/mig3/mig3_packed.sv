/* Mig3 packed unit (P extension, packed SIMD), EX, combinational: the value for rd of a
 * packed instruction.
 *
 * The library's packed blocks (rtl/lib/numeric/packed) on rs1 and rs2 as lanes of 8 or 16
 * bits (dec.pk, Mig3Pkg pk_ctrl_t): PADD.B, PADD.H, PSUB.B, PSUB.H by PackedAdd, every lane
 * wrapping alone. Saturation, averaging, compares, shifts and multiplies come in later steps
 * (rtl/design/mig3/p_profile.md); they take PackedAdd's carries and overflows, not used yet.
 *
 * Mig3Core instantiates it in EX, for the instruction in EX; result is rd's value (rd_src
 * RD_PACKED).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig3Packed import Mig3Pkg::*; (
    // Only pk is used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t dec,       // the instruction taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t    rs1_data,
    input  word_t    rs2_data,
    output word_t    result
);
    // The carry and the signed overflow at every byte's top bit: for saturation, averaging
    // and compares, later.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [WIDTH/8-1:0] co;
    logic [WIDTH/8-1:0] ov;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/design/mig3/packed_unit
    PackedAdd #(.WIDTH(WIDTH)) u_packed_add(
        .a(rs1_data), .b(rs2_data), .sub(dec.pk.sub), .lane(dec.pk.lane), .sum(result), .co,
        .ov);

endmodule
