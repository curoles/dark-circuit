/* 32-bit integer multiplier: product = a * b, each operand signed or unsigned,
 * combinational, behavioral.
 *
 * Author: Igor Lesik
 *
 * a_signed=1: a is two's complement, else unsigned; the same for b. product is the
 * full 64-bit product, two's complement when an operand is signed (for example the
 * RISC-V MULH, MULHSU, MULHU take its upper half, MUL its lower half).
 */
module Int32Mul (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        a_signed,
    input  wire        b_signed,
    output wire [63:0] product
);
    // Operands extended to 33 bits by their sign (signed) or by 0 (unsigned); the 66-bit
    // signed product of those is exact, its lower 64 bits are the result.
    wire signed [32:0] sa;
    wire signed [32:0] sb;
    // The upper 2 bits only repeat the sign of the 64-bit result.
    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [65:0] full;
    /* verilator lint_on UNUSEDSIGNAL */

    assign sa      = {a_signed & a[31], a};
    assign sb      = {b_signed & b[31], b};
    assign full    = sa * sb;
    assign product = full[63:0];

endmodule
