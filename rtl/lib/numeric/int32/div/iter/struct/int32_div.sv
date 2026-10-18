/* 32-bit integer divider: quotient and remainder, signed or unsigned, iterative
 * (Divider, 32 clocks), made of blocks, parts and gates.
 *
 * Author: Igor Lesik
 *
 * Same ports and timing as the behave version, see there. Negation is -x = ~x + 1
 * (Inv, Incr); Mux2 picks the magnitudes for Divider and the signed results. Signs and
 * flags are registered on start (DffSyncRstEn, reset 0): div_by_zero is NorReduce of the
 * divisor, overflow is signed_op && dividend == 0x80000000 (CmpEq) && divisor all ones
 * (AndReduce).
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
    output wire        div_by_zero,
    output wire        overflow
);
    localparam [31:0] MIN = 32'h8000_0000;    // -2^31

    wire        a_neg;          // dividend is signed and negative
    wire        b_neg;
    wire [31:0] a_inv;
    wire [31:0] b_inv;
    wire [31:0] a_minus;        // -dividend
    wire [31:0] b_minus;
    wire [31:0] a_mag;          // magnitudes for Divider
    wire [31:0] b_mag;
    wire [31:0] u_quotient;     // results of Divider, magnitudes
    wire [31:0] u_remainder;
    wire [31:0] q_inv;
    wire [31:0] r_inv;
    wire [31:0] q_minus;
    wire [31:0] r_minus;
    wire        neg_q_in;       // operand signs differ
    wire        zero_in;        // divisor is 0
    wire        a_min;          // dividend is 0x80000000
    wire        b_ones;         // divisor is all ones
    wire        ovf_in;
    wire        idle;
    wire        load;           // start && !busy: take signs and flags
    wire        neg_q;          // negate the quotient
    wire        neg_r;          // negate the remainder
    // Carries of the negations: not used (they only tell that the value was 0).
    /* verilator lint_off UNUSEDSIGNAL */
    wire        a_co;
    wire        b_co;
    wire        q_co;
    wire        r_co;
    /* verilator lint_on UNUSEDSIGNAL */

    // Magnitudes.
    And2 #(1)  u_and2_a_neg(.in1(signed_op), .in2(dividend[31]), .out(a_neg));
    And2 #(1)  u_and2_b_neg(.in1(signed_op), .in2(divisor[31]), .out(b_neg));
    Inv  #(32) u_inv_a(.in(dividend), .out(a_inv));
    Inv  #(32) u_inv_b(.in(divisor), .out(b_inv));
    Incr #(.WIDTH(32), .GROUP(6)) u_incr_a(.in(a_inv), .out(a_minus), .co(a_co));
    Incr #(.WIDTH(32), .GROUP(6)) u_incr_b(.in(b_inv), .out(b_minus), .co(b_co));
    Mux2 #(32) u_mux2_a_mag(.in0(dividend), .in1(a_minus), .sel(a_neg), .out(a_mag));
    Mux2 #(32) u_mux2_b_mag(.in0(divisor), .in1(b_minus), .sel(b_neg), .out(b_mag));

    Divider #(.WIDTH(32)) u_divider(
        .clk, .rst_n, .start, .dividend(a_mag), .divisor(b_mag), .busy, .done,
        .quotient(u_quotient), .remainder(u_remainder));

    // Signs and flags of the operands, taken with them (start while busy is ignored).
    Xor2      #(1)  u_xor2_neg_q(.in1(a_neg), .in2(b_neg), .out(neg_q_in));
    NorReduce #(32) u_nor_reduce_zero(.in(divisor), .out(zero_in));
    CmpEq     #(32) u_cmp_eq_min(.in1(dividend), .in2(MIN), .eq(a_min));
    AndReduce #(32) u_and_reduce_ones(.in(divisor), .out(b_ones));
    And3      #(1)  u_and3_ovf(.in1(signed_op), .in2(a_min), .in3(b_ones), .out(ovf_in));
    Inv       #(1)  u_inv_busy(.in(busy), .out(idle));
    And2      #(1)  u_and2_load(.in1(start), .in2(idle), .out(load));
    DffSyncRstEn #(4) u_dff_sync_rst_en_flags(
        .clk, .rst_n, .en(load), .in({neg_q_in, a_neg, zero_in, ovf_in}),
        .out({neg_q, neg_r, div_by_zero, overflow}));

    // Signed results.
    Inv  #(32) u_inv_q(.in(u_quotient), .out(q_inv));
    Inv  #(32) u_inv_r(.in(u_remainder), .out(r_inv));
    Incr #(.WIDTH(32), .GROUP(6)) u_incr_q(.in(q_inv), .out(q_minus), .co(q_co));
    Incr #(.WIDTH(32), .GROUP(6)) u_incr_r(.in(r_inv), .out(r_minus), .co(r_co));
    Mux2 #(32) u_mux2_quotient(.in0(u_quotient), .in1(q_minus), .sel(neg_q), .out(quotient));
    Mux2 #(32) u_mux2_remainder(.in0(u_remainder), .in1(r_minus), .sel(neg_r), .out(remainder));

endmodule
