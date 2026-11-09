/* UART receiver: receives asynchronous serial frames on rx, a byte a frame; made of blocks,
 * parts and gates.
 *
 * Same ports and behavior as the behave version (see there). SignalClockSync (2 stages) brings
 * rx into clk's domain. A Counter counts the ticks of a frame from its start edge (wrapping
 * every 16), another the bits decided; DffEns keep the samples at ticks 7 and 8, Maj3 votes
 * at tick 9. The bit decided is classified from the bit count and the format kept at the start
 * (5 + data_bits by a RippleCarryAdder, + 1 by Incr for the parity bit's place): the start bit
 * (count 0), a data bit (count <= data bits: CmpGe), the parity bit (count = data bits + 1 with
 * parity: CmpEq), else the first stop bit, which ends the frame. A Decoder of the bit count
 * steers each data bit into its place of out_data (DffEn per bit, cleared at the start).
 *
 *   rx --SignalClockSync--> rx_s --> start edge (last, at ticks) --> Counter ticks
 *   rx_s --DffEn at 7, 8--> Maj3 at 9 --> start check / data bit / parity / stop --> out_*
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module UartRx import UartPkg::*; (
    input  wire        clk,
    input  wire        rst_n,       // synchronous reset, active low
    input  wire        tick,        // OVERSAMPLE ticks a bit
    input  data_bits_t data_bits,   // 5 + data_bits data bits
    input  parity_e    parity,
    input  wire        rx,          // the serial line: a pin, asynchronous to clk
    output wire        out_valid,   // a frame is received: for one clock
    output wire [7:0]  out_data,
    output wire        frame_err,   // its stop bit was 0
    output wire        parity_err   // its parity bit was wrong
);
    localparam CW = $clog2(OVERSAMPLE);

    wire          rx_s;             // rx in clk's domain
    wire          rx_s_n;
    wire          busy;             // a frame is received
    wire          busy_n;
    wire          idle_tick;        // a tick while idle
    wire          busy_tick;        // a tick of a frame
    wire          last;             // rx_s at the idle tick before
    wire          last_next;
    wire          last_idle;        // last, or rx_s at an idle tick
    wire          start;            // a falling edge at an idle tick: maybe a start bit
    wire [CW-1:0] count;            // ticks since the start edge, in the bit
    wire [3:0]    bit_n;            // the bit decided next: 0 the start bit
    wire          at7, at8, at9;    // count is 7, 8, 9
    wire          take7, take8;
    wire          s7, s8;           // the samples at ticks 7 and 8
    wire          maj;              // the bit: the majority of s7, s8 and rx_s at tick 9
    wire          maj_n;
    wire          decide;           // a bit is decided now (tick 9)
    wire [3:0]    n_data_in;        // 5 + data_bits
    wire [3:0]    n_data;           // the data bits of the frame, kept at its start
    wire [3:0]    n_data_inc;       // ... + 1: the place of the parity bit
    wire [1:0]    par;              // the parity of the frame, kept at its start
    wire          par_en;
    wire          is_start;         // the bit decided is the start bit
    wire          not_start;
    wire          le_data;          // bit_n <= n_data
    wire          is_data;          // a data bit
    wire          at_par;           // bit_n is the parity bit's place
    wire          is_par;           // the parity bit (with parity)
    wire          is_data_or_par;
    wire          is_stop;          // the first stop bit: the frame ends
    wire          no_start;         // the start bit is not 0 at its middle: a glitch
    wire          done;             // the frame ends now
    wire          busy_set;
    wire          busy_clr;
    wire          busy_clr_n;
    wire          busy_next;
    wire [7:0]    data_en;          // data bit k is decided now
    wire [7:0]    data_wr;          // ... or the start clears it
    wire          start_n;
    wire          maj_in;           // the bit, 0 at the start (clears out_data)
    wire          p;                // the parity of the data bits so far
    wire          p_next;
    wire          p_in;
    wire          p_en;
    wire          data_dec;         // a data bit is decided now
    wire          exp_par;          // the parity bit the data asks for
    wire          par_bad;          // the parity bit decided is wrong
    wire          par_dec;          // the parity bit is decided now
    wire          perr_none;        // the frame ends without parity: no parity error
    wire          perr_en;
    wire          perr_in;
    wire          par_en_n;
    // Not needed: the counters wrap or are loaded; the small sums do not carry out; at_bit only
    // where data bits are (1 to 8).
    /* verilator lint_off UNUSEDSIGNAL */
    wire          co_count, co_bit, co_n, co_inc;
    wire [15:0]   at_bit;           // bit_n one-hot
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/io/uart/design
    // The pin is a flop's output of the far end (SRC_FLOP 0).
    SignalClockSync #(.WIDTH(1), .STAGES(2), .SRC_FLOP(0)) u_signal_clock_sync(
        .clk1(clk), .clk2(clk), .in(rx), .out(rx_s));
    Inv  #(1) u_inv_rx(.in(rx_s), .out(rx_s_n));

    // A start: the line 0 at an idle tick after 1 at the idle tick before.
    Inv  #(1) u_inv_busy(.in(busy), .out(busy_n));
    And2 #(1) u_and2_idle_tick(.in1(tick), .in2(busy_n), .out(idle_tick));
    And2 #(1) u_and2_busy_tick(.in1(tick), .in2(busy), .out(busy_tick));
    And3 #(1) u_and3_start(.in1(idle_tick), .in2(last), .in3(rx_s_n), .out(start));

    // Ticks since the start edge, bits decided.
    Counter #(.WIDTH(CW)) u_counter_ticks(
        .clk, .rst_n, .load(start), .in({CW{1'b0}}), .up_down(1'b1), .count_en(busy_tick),
        .out(count), .co(co_count));
    CmpEq #(CW) u_cmp_eq_7(.in1(count), .in2(CW'(7)), .eq(at7));
    CmpEq #(CW) u_cmp_eq_8(.in1(count), .in2(CW'(8)), .eq(at8));
    CmpEq #(CW) u_cmp_eq_9(.in1(count), .in2(CW'(9)), .eq(at9));
    And2 #(1) u_and2_take7(.in1(busy_tick), .in2(at7), .out(take7));
    And2 #(1) u_and2_take8(.in1(busy_tick), .in2(at8), .out(take8));
    And2 #(1) u_and2_decide(.in1(busy_tick), .in2(at9), .out(decide));
    DffEn #(1) u_dff_en_s7(.clk, .en(take7), .in(rx_s), .out(s7));
    DffEn #(1) u_dff_en_s8(.clk, .en(take8), .in(rx_s), .out(s8));
    Maj3 #(1) u_maj3(.in1(s7), .in2(s8), .in3(rx_s), .out(maj));
    Inv  #(1) u_inv_maj(.in(maj), .out(maj_n));
    Counter #(.WIDTH(4)) u_counter_bits(
        .clk, .rst_n, .load(start), .in(4'd0), .up_down(1'b1), .count_en(decide),
        .out(bit_n), .co(co_bit));

    // The format, kept at the start.
    RippleCarryAdder #(4) u_ripple_carry_adder_n(
        .in1({2'b00, data_bits}), .in2(4'd5), .ci(1'b0), .co(co_n), .sum(n_data_in));
    DffEn #(6) u_dff_en_format(.clk, .en(start), .in({n_data_in, parity}), .out({n_data, par}));
    Incr #(.WIDTH(4)) u_incr_par_at(.in(n_data), .out(n_data_inc), .co(co_inc));
    OrReduce #(2) u_or_reduce_par(.in(par), .out(par_en));

    // What the bit decided is.
    NorReduce #(4) u_nor_reduce_start(.in(bit_n), .out(is_start));
    Inv  #(1) u_inv_start(.in(is_start), .out(not_start));
    CmpGe #(4) u_cmp_ge_data(.in1(n_data), .in2(bit_n), .ge(le_data));
    And2 #(1) u_and2_is_data(.in1(not_start), .in2(le_data), .out(is_data));
    CmpEq #(4) u_cmp_eq_par(.in1(bit_n), .in2(n_data_inc), .eq(at_par));
    And2 #(1) u_and2_is_par(.in1(at_par), .in2(par_en), .out(is_par));
    Or2  #(1) u_or2_data_or_par(.in1(is_data), .in2(is_par), .out(is_data_or_par));
    Nor2 #(1) u_nor2_is_stop(.in1(is_start), .in2(is_data_or_par), .out(is_stop));
    And3 #(1) u_and3_no_start(.in1(decide), .in2(is_start), .in3(maj), .out(no_start));
    And2 #(1) u_and2_done(.in1(decide), .in2(is_stop), .out(done));

    // busy: set at the start, cleared by a glitch (no start bit) and at the frame's end.
    Or2  #(1) u_or2_busy_clr(.in1(no_start), .in2(done), .out(busy_clr));
    Inv  #(1) u_inv_busy_clr(.in(busy_clr), .out(busy_clr_n));
    And2 #(1) u_and2_busy_set(.in1(busy), .in2(busy_clr_n), .out(busy_set));
    Or2  #(1) u_or2_busy(.in1(start), .in2(busy_set), .out(busy_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_busy(.clk, .rst_n, .in(busy_next), .out(busy));

    // last: rx_s at every idle tick, the stop bit at the frame's end (a stop bit 0 waits).
    Mux2 #(1) u_mux2_last_idle(.in0(last), .in1(rx_s), .sel(idle_tick), .out(last_idle));
    Mux2 #(1) u_mux2_last(.in0(last_idle), .in1(maj), .sel(done), .out(last_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_last(.clk, .rst_n, .in(last_next), .out(last));

    // The data bits into their places; all cleared at the start.
    Decoder #(.SIZE(4)) u_decoder_bit(.in(bit_n), .en(1'b1), .out(at_bit));
    And2 #(1) u_and2_data_dec(.in1(decide), .in2(is_data), .out(data_dec));
    And2 #(8) u_and2_data_en(.in1(at_bit[8:1]), .in2({8{data_dec}}), .out(data_en));
    Or2  #(8) u_or2_data_wr(.in1(data_en), .in2({8{start}}), .out(data_wr));
    Inv  #(1) u_inv_start_n(.in(start), .out(start_n));
    And2 #(1) u_and2_maj_in(.in1(maj), .in2(start_n), .out(maj_in));
    for (genvar k = 0; k < 8; k++) begin: g_data
        DffEn #(1) u_dff_en(.clk, .en(data_wr[k]), .in(maj_in), .out(out_data[k]));
    end

    // The parity of the data bits, and the parity bit's check.
    Or2  #(1) u_or2_p_en(.in1(start), .in2(data_dec), .out(p_en));
    Xor2 #(1) u_xor2_p(.in1(p), .in2(maj), .out(p_next));
    And2 #(1) u_and2_p_in(.in1(p_next), .in2(start_n), .out(p_in));    // 0 at the start
    DffEn #(1) u_dff_en_p(.clk, .en(p_en), .in(p_in), .out(p));
    // Odd parity: par[1] (PARITY_ODD is 2'b10).
    Xor2 #(1) u_xor2_exp(.in1(p), .in2(par[1]), .out(exp_par));
    Xor2 #(1) u_xor2_bad(.in1(maj), .in2(exp_par), .out(par_bad));
    And2 #(1) u_and2_par_dec(.in1(decide), .in2(is_par), .out(par_dec));
    Inv  #(1) u_inv_par_en(.in(par_en), .out(par_en_n));
    And2 #(1) u_and2_perr_none(.in1(done), .in2(par_en_n), .out(perr_none));
    Or2  #(1) u_or2_perr_en(.in1(par_dec), .in2(perr_none), .out(perr_en));
    And2 #(1) u_and2_perr_in(.in1(par_bad), .in2(par_dec), .out(perr_in));
    DffEn #(1) u_dff_en_perr(.clk, .en(perr_en), .in(perr_in), .out(parity_err));

    // The frame's end: frame_err from the stop bit, out_valid for a clock.
    DffEn #(1) u_dff_en_ferr(.clk, .en(done), .in(maj_n), .out(frame_err));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_valid(.clk, .rst_n, .in(done), .out(out_valid));

    // See the behave version.
    `DC_ASSERT_NEXT(a_valid_one_clock, out_valid, !out_valid)

endmodule
