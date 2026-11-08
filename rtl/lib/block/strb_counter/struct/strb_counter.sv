/* Strobed counter: a counter that is also a strobed register; made of blocks and gates.
 *
 * Same ports and behavior as the behave version (see there). Incr gives q + 1; per byte a
 * Mux2 keeps the byte or takes wdata's (wstrb[b]); a Mux2 takes those bytes on we, else
 * the count; one DffSyncRstEn with RST_VAL, enabled by we | inc (Or2).
 *
 *   q --> Incr --------------------------------> in0 \
 *   q, wdata --> per byte Mux2 (wstrb[b]) -----> in1  Mux2 (we) --> DffSyncRstEn --> q
 *   we, inc --> Or2 ------------------------------------------------> en
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module StrbCounter #(
    parameter             WIDTH   = 64,                 // bits held
    parameter [WIDTH-1:0] RST_VAL = '0,                 // value after reset
    localparam            NBYTES  = (WIDTH + 7) / 8     // bytes, the last one may be partial
)(
    input  wire              clk,
    input  wire              rst_n,     // synchronous reset, active low
    input  wire              we,        // this register is written now
    input  wire [NBYTES-1:0] wstrb,     // bytes written
    input  wire [WIDTH-1:0]  wdata,     // the bytes, each at its place
    input  wire              inc,       // count now (unless written)
    output wire [WIDTH-1:0]  q
);
    `DC_STATIC_ASSERT(a_width, WIDTH >= 1)

    wire [WIDTH-1:0] count;     // q + 1
    wire [WIDTH-1:0] written;   // q with the bytes of the write
    wire [WIDTH-1:0] next;
    wire             en;
    // The carry out of all ones: the count wraps to 0.
    /* verilator lint_off UNUSEDSIGNAL */
    wire             co;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/strb_counter/design
    Incr #(.WIDTH(WIDTH)) u_incr(.in(q), .out(count), .co);
    for (genvar b = 0; b < NBYTES; b++) begin: g_byte
        localparam LO = 8 * b;                                      // its first bit
        localparam BW = (8 * (b + 1) <= WIDTH) ? 8 : WIDTH - 8 * b; // its bits
        Mux2 #(BW) u_mux2(.in0(q[LO +: BW]), .in1(wdata[LO +: BW]), .sel(wstrb[b]),
                          .out(written[LO +: BW]));
    end
    Mux2 #(WIDTH) u_mux2_next(.in0(count), .in1(written), .sel(we), .out(next));
    Or2  #(1)     u_or2_en(.in1(we), .in2(inc), .out(en));
    DffSyncRstEn #(.WIDTH(WIDTH), .RST_VAL(RST_VAL)) u_dff_sync_rst_en(
        .clk, .rst_n, .en, .in(next), .out(q));

    // See the behave version.
    `DC_ASSERT_NEXT(a_kept, !we && !inc, $stable(q))
    `DC_ASSERT_NEXT(a_count, !we && inc, q == WIDTH'($past(q) + 1'b1))

endmodule
