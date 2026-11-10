/* Fp package: what every floating-point format of the library shares, the rounding modes
 * and the decision to round up, the exception flags, the classes, the operations of the
 * fused multiply-add and of sign injection, and the rules that differ between ISAs as
 * parameters of the blocks (a NaN in a minimum, an invalid conversion to an integer).
 *
 * Their encodings are RISC-V's (frm and fflags of fcsr), so a core wires them as they are;
 * the package itself knows nothing about RISC-V. The flags are also SoftFloat's bits
 * (softfloat_flag_*), the reference of the tests (TestFloat, kb rtl/lib/numeric/fp32/design).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package FpPkg;

    // Rounding mode (IEEE 754 rounding-direction attributes).
    typedef enum logic [2:0] {
        RM_RNE = 3'b000,    // to nearest, ties to even
        RM_RTZ = 3'b001,    // toward zero
        RM_RDN = 3'b010,    // down, toward -infinity
        RM_RUP = 3'b011,    // up, toward +infinity
        RM_RMM = 3'b100     // to nearest, ties away from zero (max magnitude)
    } rm_e;

    // @kb: rtl/lib/numeric/fp32/design
    // Round up: increment the kept bits of a value by mode m, its sign s, the last kept bit
    // lsb, the guard bit (the first one dropped) and sticky (the OR of the others below).
    // Encodings other than the five round toward zero (a core traps them).
    function automatic logic round_up(input rm_e m, input logic s, input logic lsb,
                                      input logic guard, input logic sticky);
        case (m)
            RM_RNE:  return guard && (sticky || lsb);
            RM_RDN:  return s && (guard || sticky);
            RM_RUP:  return !s && (guard || sticky);
            RM_RMM:  return guard;
            default: return 1'b0;                   // RTZ
        endcase
    endfunction

    // Exception flags of an operation, accrued by software (fflags).
    typedef struct packed {
        logic nv;   // invalid operation
        logic dz;   // divide by zero
        logic of;   // overflow
        logic uf;   // underflow: tiny after rounding and inexact
        logic nx;   // inexact
    } flags_t;

    // Operation of a fused multiply-add unit (Fp32Fma): a, b and c are a core's rs1, rs2
    // and rs3.
    typedef enum logic [2:0] {
        FMA_MADD,   // a * b + c
        FMA_MSUB,   // a * b - c
        FMA_NMSUB,  // -(a * b) + c
        FMA_NMADD,  // -(a * b) - c
        FMA_ADD,    // a + b
        FMA_SUB,    // a - b
        FMA_MUL     // a * b
    } fma_op_e;

    // The class of a value (Fp32Class): IEEE 754's ten, one set. The order of the fields
    // (the last one bit 0) is the bits of RISC-V's FCLASS result.
    typedef struct packed {
        logic qnan;             // 9: a quiet NaN
        logic snan;             // 8: a signalling NaN
        logic pos_inf;          // 7
        logic pos_normal;       // 6
        logic pos_subnormal;    // 5
        logic pos_zero;         // 4
        logic neg_zero;         // 3
        logic neg_subnormal;    // 2
        logic neg_normal;       // 1
        logic neg_inf;          // 0
    } class_t;

    // Sign injection (Fp32SignInject): a's magnitude with a new sign.
    typedef enum logic [1:0] {
        SGNJ_COPY,  // b's sign (IEEE copySign; RISC-V FSGNJ.S)
        SGNJ_NEG,   // the inverse of b's sign (RISC-V FSGNJN.S)
        SGNJ_XOR    // a's sign xor b's (RISC-V FSGNJX.S)
    } sgnj_op_e;

    // What a NaN operand does to a minimum or maximum (Fp32MinMax). Both rules order -0
    // below +0 and flag NV for a signalling NaN.
    typedef enum logic {
        MINMAX_NUMBER,  // IEEE 754-2019 minimumNumber, maximumNumber: a NaN loses to a
                        // number, two NaNs give the default NaN (RISC-V FMIN.S, FMAX.S)
        MINMAX_NAN      // IEEE 754-2019 minimum, maximum: a NaN operand gives the default
                        // NaN (RISC-V Zfa FMINM.S, FMAXM.S)
    } minmax_nan_e;

    // The integer of an invalid conversion to an integer (a NaN, or out of range after
    // rounding; IEEE 754 leaves it open), Fp32ToInt. NV in every case.
    typedef enum logic {
        TOINT_RISCV,    // a NaN or too large: the largest integer; too small: the smallest
        TOINT_ARM       // as RISC-V, but a NaN gives 0
    } toint_invalid_e;

endpackage
