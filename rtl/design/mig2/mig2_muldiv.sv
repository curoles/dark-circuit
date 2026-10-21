`include "dark_circuit_assert.svh"

/* Mig2 multiply and divide unit (M extension), EX.
 *
 * MUL, MULH, MULHSU, MULHU: Int32Mul, combinational, one cycle. DIV, DIVU, REM, REMU:
 * Int32Div, 32 clocks: in the first cycle of the instruction in EX the division starts,
 * and stall=1 keeps the instruction in EX until the result is there (34 cycles in EX:
 * start, 32 steps, then the result). The instruction and its registers do not change
 * meanwhile, so rs1_data is still the dividend at the end. Results of the special cases
 * as RISC-V M defines them (no traps): divide by 0 gives quotient all ones and remainder
 * the dividend; signed overflow (-2^31 / -1) gives quotient -2^31 and remainder 0.
 */
module Mig2MulDiv import Mig2Pkg::*, RiscvPkg::*; (
    input  wire              clk,
    input  wire              rst_n,       // synchronous reset, active low
    input  wire              valid,       // instruction in EX is valid
    // Only muldiv and funct3 are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t         dec,
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t            rs1_data,
    input  word_t            rs2_data,
    output wire              stall,       // division of the instruction in EX not done yet
    output word_t            result
);
    logic        muldiv;        // M instruction in EX
    logic        div;           // DIV, DIVU, REM, REMU
    logic        rem;           // REM, REMU
    logic        mul_lo;        // MUL: lower half of the product
    logic        a_signed;      // MULH, MULHSU: rs1 is signed
    logic        b_signed;      // MULH: rs2 is signed
    logic        div_signed;    // DIV, REM
    logic        start;
    logic [63:0] product;
    word_t       product_lo;
    word_t       product_hi;
    logic        busy;
    logic        done;          // last step of the division; results are valid after it
    logic        div_ready;     // the division finished in the clock before
    word_t       quotient;
    word_t       remainder;
    logic        div_by_zero;
    logic        overflow;

    // Operation from funct3.
    assign muldiv     = valid && dec.muldiv;
    assign div        = dec.funct3 == F3_DIV || dec.funct3 == F3_DIVU || dec.funct3 == F3_REM || dec.funct3 == F3_REMU;
    assign rem        = dec.funct3 == F3_REM || dec.funct3 == F3_REMU;
    assign mul_lo     = dec.funct3 == F3_MUL;
    assign a_signed   = dec.funct3 == F3_MULH || dec.funct3 == F3_MULHSU;
    assign b_signed   = dec.funct3 == F3_MULH;
    assign div_signed = dec.funct3 == F3_DIV || dec.funct3 == F3_REM;
    assign start      = muldiv && div && !busy && !div_ready;

    Int32Mul u_int32_mul(.a(rs1_data), .b(rs2_data), .a_signed, .b_signed, .product);

    Int32Div u_int32_div(
        .clk, .rst_n, .start, .dividend(rs1_data), .divisor(rs2_data), .signed_op(div_signed),
        .busy, .done, .quotient, .remainder, .div_by_zero, .overflow);

    always_ff @(posedge clk)
        if (!rst_n) div_ready <= 1'b0;
        else        div_ready <= done;

    assign stall = muldiv && div && !div_ready;

    // A division runs only while its instruction is in EX: nothing removes a stalled
    // instruction from EX (no interrupts yet).
    `DC_ASSERT(a_busy_has_div, !busy || (muldiv && div))
    // The header's promise: the instruction and its registers do not change during the
    // division, so rs1_data is still the dividend at the end (REM by 0 returns it).
    `DC_ASSERT_NEXT(a_div_inputs_held, stall,
                    $stable(rs1_data) && $stable(rs2_data) && $stable(dec.funct3))

    assign product_lo = product[31:0];
    assign product_hi = product[63:32];

    always_comb
        if (!div)             result = mul_lo ? product_lo : product_hi;
        else if (div_by_zero) result = rem ? rs1_data : '1;
        else if (overflow)    result = rem ? '0 : 32'h8000_0000;
        else                  result = rem ? remainder : quotient;

endmodule
