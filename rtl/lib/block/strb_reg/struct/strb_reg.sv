/* Strobed register: a register written byte by byte; made of gates.
 *
 * Same ports and behavior as the behave version (see there). Per byte a DffSyncRstEn (of 8
 * bits, the last one of WIDTH % 8 when WIDTH is not a multiple of 8) with its part of
 * RST_VAL, enabled by we & wstrb[b] (And2).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module StrbReg #(
    parameter             WIDTH   = 32,                 // bits held
    parameter [WIDTH-1:0] RST_VAL = '0,                 // value after reset
    localparam            NBYTES  = (WIDTH + 7) / 8     // bytes, the last one may be partial
)(
    input  wire              clk,
    input  wire              rst_n,     // synchronous reset, active low
    input  wire              we,        // this register is written now
    input  wire [NBYTES-1:0] wstrb,     // bytes written
    input  wire [WIDTH-1:0]  wdata,     // the bytes, each at its place
    output wire [WIDTH-1:0]  q
);
    `DC_STATIC_ASSERT(a_width, WIDTH >= 1)

    // @kb: rtl/lib/block/strb_reg/design
    for (genvar b = 0; b < NBYTES; b++) begin: g_byte
        localparam LO = 8 * b;                                      // its first bit
        localparam BW = (8 * (b + 1) <= WIDTH) ? 8 : WIDTH - 8 * b; // its bits
        wire en;    // this byte is written now
        And2 #(1) u_and2(.in1(we), .in2(wstrb[b]), .out(en));
        DffSyncRstEn #(.WIDTH(BW), .RST_VAL(RST_VAL[LO +: BW])) u_dff_sync_rst_en(
            .clk, .rst_n, .en, .in(wdata[LO +: BW]), .out(q[LO +: BW]));
    end

    // Without a write the register keeps its value.
    `DC_ASSERT_NEXT(a_kept, !we, $stable(q))

endmodule
