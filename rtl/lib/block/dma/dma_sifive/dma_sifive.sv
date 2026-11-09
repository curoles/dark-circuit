/* DmaSifive: a DMA with SiFive's PDMA register map (DmaSifivePkg) behind the register port
 * and N_CHANNELS channels on one memory channel, the device top, wiring only.
 *
 * DmaSifiveRegs (the map, a channel's registers every 0x1000) controls DmaEngine (the
 * channels, a round-robin arbiter, one mover: any alignment, one transaction in flight).
 * Software claims a channel, writes NextSource, NextDestination, NextBytes (and NextConfig),
 * and sets run: the transfer copies NextBytes bytes from the source to the destination, the
 * Exec registers show it going, and at its end done is set (an interrupt with doneIE) and
 * run cleared, unless NextConfig.repeat starts it again. Writing run 0 stops a transfer after
 * the transaction offered or in flight. irq[2c] is channel c's done, irq[2c + 1] its error
 * (levels: PLIC sources); error is never set yet (the memory channel has no error answer).
 * The choices where SiFive's manual and Linux's driver are silent or differ: kb
 * rtl/lib/block/dma/design.
 *
 *     register port --> DmaSifiveRegs --start, stop--> DmaEngine --> memory channel
 *                            ^  busy, done, Exec <-------+
 *                            +--> irq
 *
 * One file for the behave and the struct library: the parts of the library it is built with
 * give the version.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DmaSifive import DmaSifivePkg::*; #(
    parameter  N_CHANNELS = 4,                      // the FU540 has 4
    parameter  ADDR_WIDTH = 32,                     // the memory's byte address, 64 at most
    parameter  DATA_WIDTH = 64,                     // the memory channel's beat
    parameter  LEN_WIDTH  = 32,                     // bits of a byte count, 64 at most
    localparam N          = N_CHANNELS,
    localparam ADDR_BITS  = CHAN_BITS + ((N > 1) ? $clog2(N) : 0),  // bits of req_addr
    localparam STRB_WIDTH = DATA_WIDTH / 8
)(
    input  wire                  clk,
    input  wire                  rst_n,             // synchronous reset, active low
    // Register port
    input  wire                  req_valid,
    output wire                  req_ready,
    input  wire                  req_we,            // 1 write, 0 read
    input  wire [ADDR_BITS-1:0]  req_addr,          // byte address inside the DMA
    input  wire [31:0]           req_wdata,
    input  wire [3:0]            req_wstrb,         // bytes written
    output wire                  rsp_valid,         // the answer to a read
    output wire [31:0]           rsp_rdata,
    // Memory side
    output wire                  mem_req_valid,
    input  wire                  mem_req_ready,
    output wire                  mem_req_we,
    output wire [ADDR_WIDTH-1:0] mem_req_addr,
    output wire [2:0]            mem_req_size,
    output wire [DATA_WIDTH-1:0] mem_req_wdata,
    output wire [STRB_WIDTH-1:0] mem_req_wstrb,
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data,
    // Interrupts: 2c done, 2c + 1 error of channel c
    output wire [2*N-1:0]        irq
);
    wire [N-1:0]                 start, stop, busy, done;
    wire [N-1:0][ADDR_WIDTH-1:0] start_src, start_dst, cur_src, cur_dst;
    wire [N-1:0][LEN_WIDTH-1:0]  start_len, left;

    // @kb: rtl/lib/block/dma/design
    DmaSifiveRegs #(.N_CHANNELS(N), .ADDR_WIDTH(ADDR_WIDTH), .LEN_WIDTH(LEN_WIDTH),
                    .LOG_BEAT($clog2(STRB_WIDTH))) u_regs(
        .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_addr, .req_wdata, .req_wstrb,
        .rsp_valid, .rsp_rdata, .start, .start_src, .start_dst, .start_len, .stop, .busy,
        .done, .error_ev({N{1'b0}}), .cur_src, .cur_dst, .left, .irq);

    DmaEngine #(.N_CHANNELS(N), .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
                .LEN_WIDTH(LEN_WIDTH)) u_engine(
        .clk, .rst_n, .start, .start_src, .start_dst, .start_len, .stop, .busy, .done,
        .cur_src, .cur_dst, .left, .mem_req_valid, .mem_req_ready, .mem_req_we,
        .mem_req_addr, .mem_req_size, .mem_req_wdata, .mem_req_wstrb, .mem_rsp_valid,
        .mem_rsp_data);

endmodule
