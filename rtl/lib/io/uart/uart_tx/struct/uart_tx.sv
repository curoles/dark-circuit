/* UART transmitter: sends each byte it takes as an asynchronous serial frame on tx; made of
 * blocks and gates.
 *
 * Same ports and behavior as the behave version (see there). The frame is built in parallel
 * from the byte and the format: a Decoder of data_bits says which of bits 6 to 9 are data,
 * which one is the parity bit (Mux2 per bit, 1 above); the parity is a Parity gate of the data
 * bits the format has (And2 masks), inverted for odd parity (Xor2). The frame's bits, 7 +
 * data_bits + parity + stop2, come from two RippleCarryAdders. A DffEn holds the frame from
 * the take to the first tick; the shift register (DffSyncRst, ones at reset) loads it then and
 * shifts at every bit's end (Mux2s); a Counter counts the 16 ticks of a bit, another the bits
 * left (loaded at the take). busy and started are DffSyncRst with their set and clear terms.
 *
 *   in_data, data_bits, parity --> frame (Decoder, Mux2, Parity) --> DffEn hold
 *   hold --at start--> shift (DffSyncRst) --at bit end: >> 1, 1 in--> shift[0] = tx
 *   tick --> Counter (16 ticks) --> bit end --> Counter (bits left) --> last: !busy
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module UartTx import UartPkg::*; (
    input  wire        clk,
    input  wire        rst_n,       // synchronous reset, active low
    input  wire        tick,        // OVERSAMPLE ticks a bit
    input  data_bits_t data_bits,   // 5 + data_bits data bits
    input  parity_e    parity,
    input  wire        stop2,       // 2 stop bits, else 1
    input  wire        in_valid,    // a byte to send
    output wire        in_ready,
    input  wire [7:0]  in_data,
    output wire        tx,          // the serial line
    output wire        busy         // a byte is taken, its frame not sent yet
);
    localparam CW = $clog2(OVERSAMPLE);
    localparam FW = FRAME_MAX;

    wire          take;             // a byte is taken now
    wire [3:0]    w;                // data_bits one-hot
    wire          has6;             // the format has data bit 5 (6 data bits or more)
    wire          has7;             // ... data bit 6
    wire          par_en;           // a parity bit
    wire [3:0]    par_at_n;
    wire [7:0]    masked;           // the data bits of the format, 0 above
    wire          p;                // their parity
    wire          pbit;             // the parity bit
    wire [3:0]    par_at;           // the parity bit is bit 6 + i (i = data_bits)
    wire [3:0]    nd;               // bits 6 to 9 when not data: the parity bit or 1
    wire [FW-1:0] frame;            // the frame of in_data
    wire [3:0]    nbits_a;          // 7 + data_bits + parity
    wire [3:0]    nbits;            // ... + stop2: the bits of the frame
    wire [FW-1:0] hold;
    wire [FW-1:0] shift;
    wire [FW-1:0] shifted;          // shift >> 1, a 1 in
    wire [FW-1:0] shift_bit;        // shift, or shifted at a bit end
    wire [FW-1:0] shift_next;
    wire          started;
    wire          busy_tick;        // busy at a tick
    wire          started_n;
    wire          start;            // the frame starts now (the first tick)
    wire          run_tick;         // a tick of the frame on the line
    wire [CW-1:0] count;            // ticks of the bit so far
    wire          count_full;       // ... 15: the bit ends at this tick
    wire          bit_end;
    wire [3:0]    left;             // bits not finished yet
    wire          left_one;
    wire          last_end;         // the last bit ends now
    wire          busy_hold;        // busy stays
    wire          busy_next;
    wire          started_set;
    wire          started_hold;
    wire          started_next;
    wire          last_end_n;
    wire          take_n;
    wire          busy_n;
    // Carries out of the small sums, and a counter's carry: never 1 or not needed.
    /* verilator lint_off UNUSEDSIGNAL */
    wire          co_a, co_b, co_count, co_left;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/io/uart/design
    Inv  #(1) u_inv_busy(.in(busy), .out(busy_n));
    assign in_ready = busy_n;
    And2 #(1) u_and2_take(.in1(in_valid), .in2(in_ready), .out(take));

    // The frame: start 0, data bits 1..5 always, bits 6..8 data when the format has them, the
    // parity bit right after the data, ones above.
    Decoder #(.SIZE(2)) u_decoder_data_bits(.in(data_bits), .en(1'b1), .out(w));
    Inv  #(1) u_inv_has6(.in(w[0]), .out(has6));                // 6 data bits or more
    Or2  #(1) u_or2_has7(.in1(w[3]), .in2(w[2]), .out(has7));   // 7 or more
    OrReduce #(2) u_or_reduce_par(.in(parity), .out(par_en));
    And2 #(3) u_and2_masked(.in1(in_data[7:5]), .in2({w[3], has7, has6}), .out(masked[7:5]));
    assign masked[4:0] = in_data[4:0];
    Parity #(8) u_parity(.in(masked), .parity(p));
    // Odd parity: parity[1] (PARITY_ODD is 2'b10).
    Xor2 #(1) u_xor2_pbit(.in1(p), .in2(parity[1]), .out(pbit));
    And2 #(4) u_and2_par_at(.in1(w), .in2({4{par_en}}), .out(par_at));
    Inv  #(4) u_inv_par_at(.in(par_at), .out(par_at_n));
    Or2  #(4) u_or2_nd(.in1(par_at_n), .in2({4{pbit}}), .out(nd));
    assign frame[0]   = 1'b0;
    assign frame[5:1] = in_data[4:0];
    Mux2 #(1) u_mux2_bit6(.in0(nd[0]), .in1(in_data[5]), .sel(has6), .out(frame[6]));
    Mux2 #(1) u_mux2_bit7(.in0(nd[1]), .in1(in_data[6]), .sel(has7), .out(frame[7]));
    Mux2 #(1) u_mux2_bit8(.in0(nd[2]), .in1(in_data[7]), .sel(w[3]), .out(frame[8]));
    assign frame[9]         = nd[3];
    assign frame[FW-1:10]   = '1;

    // Bits of the frame: 7 + data_bits + parity + stop2.
    RippleCarryAdder #(4) u_ripple_carry_adder_a(
        .in1({2'b00, data_bits}), .in2(4'd7), .ci(par_en), .co(co_a), .sum(nbits_a));
    RippleCarryAdder #(4) u_ripple_carry_adder_b(
        .in1(nbits_a), .in2(4'd0), .ci(stop2), .co(co_b), .sum(nbits));

    DffEn #(FW) u_dff_en_hold(.clk, .en(take), .in(frame), .out(hold));

    // The frame on the line: it starts at the first tick after the take.
    And2 #(1) u_and2_busy_tick(.in1(busy), .in2(tick), .out(busy_tick));
    Inv  #(1) u_inv_started(.in(started), .out(started_n));
    And2 #(1) u_and2_start(.in1(busy_tick), .in2(started_n), .out(start));
    And2 #(1) u_and2_run_tick(.in1(busy_tick), .in2(started), .out(run_tick));
    Counter #(.WIDTH(CW)) u_counter_ticks(
        .clk, .rst_n, .load(start), .in({CW{1'b0}}), .up_down(1'b1), .count_en(run_tick),
        .out(count), .co(co_count));
    AndReduce #(CW) u_and_reduce_full(.in(count), .out(count_full));
    And2 #(1) u_and2_bit_end(.in1(run_tick), .in2(count_full), .out(bit_end));
    Counter #(.WIDTH(4)) u_counter_left(
        .clk, .rst_n, .load(take), .in(nbits), .up_down(1'b0), .count_en(bit_end),
        .out(left), .co(co_left));
    CmpEq #(4) u_cmp_eq_left(.in1(left), .in2(4'd1), .eq(left_one));
    And2 #(1) u_and2_last(.in1(bit_end), .in2(left_one), .out(last_end));

    // The shift register: the frame at the start, >> 1 at every bit's end, ones at reset.
    assign shifted = {1'b1, shift[FW-1:1]};
    Mux2 #(FW) u_mux2_shift_bit(.in0(shift), .in1(shifted), .sel(bit_end), .out(shift_bit));
    Mux2 #(FW) u_mux2_shift(.in0(shift_bit), .in1(hold), .sel(start), .out(shift_next));
    DffSyncRst #(.WIDTH(FW), .RST_VAL({FW{1'b1}})) u_dff_sync_rst_shift(
        .clk, .rst_n, .in(shift_next), .out(shift));
    assign tx = shift[0];

    // busy: set by a take, cleared when the last bit ends; started: set at the start, cleared
    // by a take and when the last bit ends.
    Inv  #(1) u_inv_last(.in(last_end), .out(last_end_n));
    Inv  #(1) u_inv_take(.in(take), .out(take_n));
    And2 #(1) u_and2_busy_hold(.in1(busy), .in2(last_end_n), .out(busy_hold));
    Or2  #(1) u_or2_busy(.in1(take), .in2(busy_hold), .out(busy_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_busy(.clk, .rst_n, .in(busy_next), .out(busy));
    Or2  #(1) u_or2_started_set(.in1(start), .in2(started), .out(started_set));
    And3 #(1) u_and3_started(.in1(started_set), .in2(last_end_n), .in3(take_n),
                             .out(started_hold));
    assign started_next = started_hold;
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_started(.clk, .rst_n, .in(started_next),
                                                   .out(started));

    // See the behave version.
    `DC_ASSERT(a_idle_line, busy || tx)

endmodule
