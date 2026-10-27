/* Divider: quotient and remainder of unsigned integers, one quotient bit per clock
 * (restoring division), made of blocks, parts and gates.
 *
 * Same ports and timing as the behave version, see there. Registers d (divisor), q
 * (dividend bits not used yet, then quotient bits) and r (partial remainder) are loaded
 * on start and stepped while busy; a Counter counts the WIDTH steps down, busy is
 * count != 0, done is count == 1. One step: shifted = {r, top bit of q};
 * KoggeStoneAdder computes shifted + ~d + 1 = shifted - d, its carry out is "fits"
 * (no borrow); Mux2 keeps shifted or takes the difference as the new r, and fits is
 * the new quotient bit.
 * Early start (EARLY_START=1, see the behave version): PriorityEncoder finds the highest
 * set bit hi of the dividend; steps = hi + 1 (Incr; at least 1, hi is 0 for a dividend
 * of 0), and BarrelShifter shifts the dividend left by WIDTH - steps = ~hi (WIDTH a
 * power of 2); a divisor of 0 (NorReduce): WIDTH steps, no shift.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Divider #(
    parameter WIDTH       = 32,
    parameter EARLY_START = 0           // 1: skip the leading zeros of the dividend
)(
    input  wire             clk,
    input  wire             rst_n,      // synchronous reset, active low
    input  wire             start,
    input  wire [WIDTH-1:0] dividend,
    input  wire [WIDTH-1:0] divisor,
    output wire             busy,
    output wire             done,       // 1 in the last clock of busy
    output wire [WIDTH-1:0] quotient,
    output wire [WIDTH-1:0] remainder
);
    localparam          CW    = $clog2(WIDTH + 1);
    localparam [CW-1:0] STEPS = WIDTH[CW-1:0];
    localparam [CW-1:0] ONE   = 1;

    wire             idle;      // not busy
    wire             load;      // start && !busy: take the operands
    wire             en;        // registers change: load or a step
    wire [CW-1:0]    count;     // steps left
    wire [WIDTH-1:0] d;
    wire [WIDTH-1:0] q;
    wire [WIDTH-1:0] r;
    wire [WIDTH:0]   shifted;   // r shifted left with the next dividend bit
    wire [WIDTH-1:0] d_inv;
    wire             fits;      // no borrow: d fits into shifted
    wire [WIDTH-1:0] r_next;
    wire [WIDTH-1:0] q_next;
    wire [WIDTH-1:0] q_in;
    wire [WIDTH-1:0] r_in;
    wire [CW-1:0]    steps;     // steps of the division that starts
    wire [WIDTH-1:0] q_start;   // the dividend, with the leading zeros it skips shifted out
    // Not used: the carry of the Counter; the top bit of the difference (0 when d fits,
    // see the behave version); the top bit of q shifted, which has moved into shifted.
    /* verilator lint_off UNUSEDSIGNAL */
    wire             count_co;
    wire [WIDTH:0]   diff;
    wire [WIDTH:0]   q_shifted;
    /* verilator lint_on UNUSEDSIGNAL */

    // Control.
    Inv  #(1) u_inv_busy(.in(busy), .out(idle));
    And2 #(1) u_and2_load(.in1(start), .in2(idle), .out(load));
    Or2  #(1) u_or2_en(.in1(load), .in2(busy), .out(en));

    // Early start (see the behave version for why the leading zeros can be skipped).
    if (EARLY_START != 0) begin: g_early
        localparam SIZE = $clog2(WIDTH);
        wire [SIZE-1:0] hi;             // highest set bit of the dividend, 0 if none
        wire [SIZE-1:0] hi_n;           // WIDTH-1-hi: the leading zeros
        wire [SIZE-1:0] shift;
        wire [CW-1:0]   hi_steps;       // hi + 1
        wire            div0;           // divisor 0: no skip
        // Not used: valid (a dividend of 0 takes one step, hi is 0), the carry of hi + 1.
        /* verilator lint_off UNUSEDSIGNAL */
        wire            hi_valid;
        wire            hi_co;
        /* verilator lint_on UNUSEDSIGNAL */

        PriorityEncoder #(.SIZE(SIZE)) u_priority_encoder(
            .in(dividend), .out(hi), .valid(hi_valid));
        Incr      #(.WIDTH(CW), .GROUP(CW)) u_incr(.in({1'b0, hi}), .out(hi_steps), .co(hi_co));
        Inv       #(SIZE)  u_inv_hi(.in(hi), .out(hi_n));
        NorReduce #(WIDTH) u_nor_reduce(.in(divisor), .out(div0));
        Mux2      #(CW)    u_mux2_steps(.in0(hi_steps), .in1(STEPS), .sel(div0), .out(steps));
        Mux2      #(SIZE)  u_mux2_shift(.in0(hi_n), .in1({SIZE{1'b0}}), .sel(div0), .out(shift));
        BarrelShifter #(.WIDTH(WIDTH)) u_barrel_shifter(
            .in(dividend), .shift_in_bit(1'b0), .shift, .shift_rotate(1'b1), .left_right(1'b1),
            .out(q_start));
    end else begin: g_full
        assign steps   = STEPS;
        assign q_start = dividend;
    end

    Counter #(.WIDTH(CW)) u_counter(
        .clk, .rst_n, .load, .in(steps), .up_down(1'b0), .count_en(busy), .out(count),
        .co(count_co));
    OrReduce #(CW) u_or_reduce_busy(.in(count), .out(busy));
    CmpEq    #(CW) u_cmp_eq_done(.in1(count), .in2(ONE), .eq(done));

    // One step.
    assign shifted = {r, q[WIDTH-1]};
    Inv #(WIDTH) u_inv_d(.in(d), .out(d_inv));
    KoggeStoneAdder #(.WIDTH(WIDTH + 1)) u_kogge_stone_adder(
        .in1(shifted), .in2({1'b1, d_inv}), .ci(1'b1), .co(fits), .sum(diff));
    Mux2 #(WIDTH) u_mux2_r_next(.in0(shifted[WIDTH-1:0]), .in1(diff[WIDTH-1:0]), .sel(fits),
                                .out(r_next));
    assign q_shifted = {q, fits};
    assign q_next    = q_shifted[WIDTH-1:0];

    // Registers: on load the operands (r = 0), else the step.
    Mux2 #(WIDTH) u_mux2_q_in(.in0(q_next), .in1(q_start), .sel(load), .out(q_in));
    Mux2 #(WIDTH) u_mux2_r_in(.in0(r_next), .in1({WIDTH{1'b0}}), .sel(load), .out(r_in));
    DffSyncRstEn #(WIDTH) u_dff_sync_rst_en_d(.clk, .rst_n, .en(load), .in(divisor), .out(d));
    DffSyncRstEn #(WIDTH) u_dff_sync_rst_en_q(.clk, .rst_n, .en, .in(q_in), .out(q));
    DffSyncRstEn #(WIDTH) u_dff_sync_rst_en_r(.clk, .rst_n, .en, .in(r_in), .out(r));

    assign quotient  = q;
    assign remainder = r;

endmodule
