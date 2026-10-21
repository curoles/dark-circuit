/* 32-bit integer divider: quotient and remainder, signed or unsigned, iterative
 * (Divider, 32 clocks), behavioral.
 *
 * Same handshake as Divider: start=1 while busy=0 takes the operands, busy=1 for 32
 * clocks, done=1 in the last; outputs are valid after that clock (busy=0 again) until
 * the next start.
 * signed_op=1: two's complement operands, the quotient is rounded toward zero, the
 * remainder has the sign of the dividend (dividend = quotient * divisor + remainder),
 * as in C and RISC-V. Divider works on magnitudes; the signs are taken at start and
 * applied to its results (the magnitude of -2^31 read as unsigned is right).
 * div_by_zero=1: the divisor was 0. overflow=1: signed -2^31 / -1, the quotient does
 * not fit. In both cases quotient and remainder have no defined value: the user (an
 * ISA, a language) decides what they are.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Int32Div (
    input  wire        clk,
    input  wire        rst_n,       // synchronous reset, active low
    input  wire        start,
    input  wire [31:0] dividend,
    input  wire [31:0] divisor,
    input  wire        signed_op,   // 1: two's complement, 0: unsigned
    output wire        busy,
    output wire        done,
    output wire [31:0] quotient,
    output wire [31:0] remainder,
    output logic       div_by_zero,
    output logic       overflow
);
    wire        a_neg;       // dividend is signed and negative
    wire        b_neg;
    wire [31:0] a_mag;       // magnitudes for Divider
    wire [31:0] b_mag;
    wire [31:0] u_quotient;  // results of Divider, magnitudes
    wire [31:0] u_remainder;
    logic       neg_q;       // negate the quotient: the operand signs differ
    logic       neg_r;       // negate the remainder: the dividend was negative

    assign a_neg = signed_op & dividend[31];
    assign b_neg = signed_op & divisor[31];
    assign a_mag = a_neg ? -dividend : dividend;
    assign b_mag = b_neg ? -divisor  : divisor;

    Divider #(.WIDTH(32)) u_divider(
        .clk, .rst_n, .start, .dividend(a_mag), .divisor(b_mag), .busy, .done,
        .quotient(u_quotient), .remainder(u_remainder));

    // Signs and flags of the operands, taken with them (start while busy is ignored).
    always_ff @(posedge clk)
        if (start && !busy) begin
            neg_q       <= a_neg ^ b_neg;
            neg_r       <= a_neg;
            div_by_zero <= divisor == '0;
            overflow    <= signed_op && dividend == 32'h8000_0000 && divisor == '1;
        end

    assign quotient  = neg_q ? -u_quotient  : u_quotient;
    assign remainder = neg_r ? -u_remainder : u_remainder;

endmodule
