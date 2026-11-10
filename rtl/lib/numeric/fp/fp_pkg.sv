/* Fp package: what every floating-point format of the library shares, the rounding modes and
 * the exception flags.
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

    // Exception flags of an operation, accrued by software (fflags).
    typedef struct packed {
        logic nv;   // invalid operation
        logic dz;   // divide by zero
        logic of;   // overflow
        logic uf;   // underflow: tiny after rounding and inexact
        logic nx;   // inexact
    } flags_t;

endpackage
