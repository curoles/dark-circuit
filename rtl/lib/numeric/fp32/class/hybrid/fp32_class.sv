/* Fp32 class: which of IEEE 754's ten classes x is (RISC-V FCLASS.S), one flag set,
 * hybrid.
 *
 * FpPkg::class_t has a field per class; their order (the last field bit 0) is the bits of
 * RISC-V's FCLASS result, as FpPkg's rounding modes and flags are RISC-V's encodings. From
 * Fp32Unpack's class and the sign. Hybrid (AGENTS.md): glue only.
 *
 *   x --> Fp32Unpack --> zero, subnormal, infinity, NaN, signalling NaN; sign --> class
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Fp32Class import Fp32Pkg::*, FpPkg::*; (
    input  fp32_t  x,
    output class_t c
);
    // Of x unpacked only the class and the sign are used.
    /* verilator lint_off UNUSEDSIGNAL */
    fp32_unpacked_t u;
    /* verilator lint_on UNUSEDSIGNAL */
    logic           normal;

    Fp32Unpack u_unpack(.x, .u);

    assign normal = !u.zero && !u.subnormal && !u.inf && !u.nan;

    assign c.qnan          = u.nan && !u.snan;
    assign c.snan          = u.snan;
    assign c.pos_inf       = u.inf && !u.sign;
    assign c.pos_normal    = normal && !u.sign;
    assign c.pos_subnormal = u.subnormal && !u.sign;
    assign c.pos_zero      = u.zero && !u.sign;
    assign c.neg_zero      = u.zero && u.sign;
    assign c.neg_subnormal = u.subnormal && u.sign;
    assign c.neg_normal    = normal && u.sign;
    assign c.neg_inf       = u.inf && u.sign;

endmodule
