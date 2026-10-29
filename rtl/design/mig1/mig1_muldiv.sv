/* Mig1 multiply and divide unit (M extension), EX.
 *
 * MUL, MULH, MULHSU, MULHU: Int32Mul, combinational, one cycle. DIV, DIVU, REM, REMU:
 * Int32Div, 32 clocks: in the first cycle of the instruction in EX the division starts,
 * and stall=1 keeps the instruction in EX until the result is there (34 cycles in EX:
 * start, 32 steps, then the result). The instruction and its registers do not change
 * meanwhile, so rs1_data is still the dividend at the end. Results of the special cases
 * as RISC-V M defines them (no traps): divide by 0 gives quotient all ones and remainder
 * the dividend; signed overflow (-2^31 / -1) gives quotient -2^31 and remainder 0.
 *
 * Mig1Core instantiates it in EX, for the instruction in EX. stall goes to Mig1Control,
 * which keeps the instruction in EX and holds ID and IF; result is rd's value (rd_src
 * RD_MULDIV).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig1MulDiv import Mig1Pkg::*; (
    input  wire      clk,
    input  wire      rst_n,     // synchronous reset, active low
    input  wire      valid,     // instruction in EX is valid
    // Only muldiv is used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t dec,       // the instruction taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t    rs1_data,
    input  word_t    rs2_data,
    output wire      stall,     // division of the instruction in EX not done yet
    output word_t    result
);
    logic   muldiv;         // M instruction in EX
    logic   start;          // start a division: an M divide in its first cycle in EX
    dword_t product;        // Int32Mul out
    logic   busy;
    logic   done;           // last step of the division; results are valid after it
    logic   div_ready;      // the division finished in the clock before
    word_t  quotient;
    word_t  remainder;
    logic   div_by_zero;
    logic   overflow;

    // Controls from Decode (decoded_t.muldiv); muldiv: an M instruction is in EX.
    assign muldiv = valid && dec.muldiv.en;
    assign start  = muldiv && dec.muldiv.div && !busy && !div_ready;

    Int32Mul u_int32_mul(.a(rs1_data), .b(rs2_data), .a_signed(dec.muldiv.a_signed),
                         .b_signed(dec.muldiv.b_signed), .product);

    Int32Div u_int32_div(
        .clk, .rst_n, .start, .dividend(rs1_data), .divisor(rs2_data),
        .signed_op(dec.muldiv.div_signed),
        .busy, .done, .quotient, .remainder, .div_by_zero, .overflow);

    always_ff @(posedge clk)
        if (!rst_n) div_ready <= 1'b0;
        else        div_ready <= done;

    assign stall = muldiv && dec.muldiv.div && !div_ready;

    // A division runs only while its instruction is in EX: nothing removes a stalled
    // instruction from EX (no interrupts yet).
    `DC_ASSERT(a_busy_has_div, !busy || (muldiv && dec.muldiv.div))
    // The header's promise: the instruction and its registers do not change during the
    // division, so rs1_data is still the dividend at the end (REM by 0 returns it).
    `DC_ASSERT_NEXT(a_div_inputs_held, stall,
                    $stable(rs1_data) && $stable(rs2_data) && $stable(dec.muldiv))

    always_comb
        if (!dec.muldiv.div)  result = dec.muldiv.mul_lo ? product.lo : product.hi;
        else if (div_by_zero) result = dec.muldiv.rem ? rs1_data : '1;
        else if (overflow)    result = dec.muldiv.rem ? '0 : {1'b1, {(WIDTH-1){1'b0}}};
        else                  result = dec.muldiv.rem ? remainder : quotient;

endmodule
