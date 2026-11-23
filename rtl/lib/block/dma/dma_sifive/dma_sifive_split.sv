/* DmaSifiveSplit: a DMA with SiFive's PDMA register map (DmaSifivePkg) behind the register
 * port and N_CHANNELS DMA channels, its mover's read and write channels apart, the device
 * top, wiring only.
 *
 * DmaSifiveRegs (the map, a DMA channel's registers every 0x1000) controls DmaEngine (the DMA
 * channels, a round-robin arbiter, one mover: any alignment, up to DEPTH transactions in
 * flight, kb rtl/lib/block/dma/pipelined_mover and issue_pointer). Software claims a DMA
 * channel, writes NextSource, NextDestination, NextBytes (and NextConfig), and sets run: the
 * transfer copies NextBytes bytes from the source to the destination, the Exec registers
 * show how far it has landed, and at its end done is set (an interrupt with doneIE) and run
 * cleared, unless NextConfig.repeat starts it again. Writing run 0 stops a transfer: no new
 * transaction, the one offered and the ones in flight finish (a run written meanwhile waits
 * until the DMA channel is idle). irq[2c] is DMA channel c's done, irq[2c + 1] its error
 * (levels: PLIC sources); error is never set yet (no error answer). The read channel reads
 * source beats (bursts of up to MAX_BURST when a transfer's source and destination are at
 * beat boundaries: rd_req_len, kb rtl/lib/block/dma/read_bursts), answered in order, a beat
 * an answer; the write channel writes destination beats, with WR_ACK
 * answered in order and a transaction done only at its answer. For a design whose reads and
 * writes go to different targets (Mig6Pe: the network and the local memory), so that a
 * write never waits for the answers a read's target owes; DmaSifive joins the two into one
 * memory channel. The choices where SiFive's manual and Linux's driver are silent or
 * differ: kb rtl/lib/block/dma/design.
 *
 *     register port --> DmaSifiveRegs --start, stop--> DmaEngine --> read channel
 *                            ^  busy, done, Exec <-------+     \---> write channel
 *                            +--> irq
 *
 * One file for the behave and the struct library: the parts of the library it is built with
 * give the version.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DmaSifiveSplit import DmaSifivePkg::*; #(
    parameter  N_CHANNELS = 4,                      // the FU540 has 4
    parameter  ADDR_WIDTH = 32,                     // the memory's byte address, 64 at most
    parameter  DATA_WIDTH = 64,                     // the channels' beat
    parameter  LEN_WIDTH  = 32,                     // bits of a byte count, 64 at most
    parameter  DEPTH      = 1,                      // the mover's transactions in flight
    parameter  WR_ACK     = 0,                      // the mover's writes want an answer
    parameter  MAX_BURST  = 1,                      // the mover's read bursts: 1 (none), 2, ...
    localparam LW         = (MAX_BURST > 1) ? $clog2(MAX_BURST) : 1,    // bits of rd_req_len
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
    // Read channel
    output wire                  rd_req_valid,
    input  wire                  rd_req_ready,
    output wire [ADDR_WIDTH-1:0] rd_req_addr,
    output wire [2:0]            rd_req_size,
    output wire [LW-1:0]         rd_req_len,        // beats - 1 (kb rtl/lib/block/bursts)
    input  wire                  rd_rsp_valid,
    input  wire [DATA_WIDTH-1:0] rd_rsp_data,
    // Write channel
    output wire                  wr_req_valid,
    input  wire                  wr_req_ready,
    output wire [ADDR_WIDTH-1:0] wr_req_addr,
    output wire [2:0]            wr_req_size,
    output wire [DATA_WIDTH-1:0] wr_req_wdata,
    output wire [STRB_WIDTH-1:0] wr_req_wstrb,
    output wire                  wr_req_rsp,        // wants an answer: WR_ACK
    input  wire                  wr_rsp_valid,      // a write's answer (WR_ACK)
    // Interrupts: 2c done, 2c + 1 error of DMA channel c
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
                .LEN_WIDTH(LEN_WIDTH), .DEPTH(DEPTH), .WR_ACK(WR_ACK),
                .MAX_BURST(MAX_BURST)) u_engine(
        .clk, .rst_n, .start, .start_src, .start_dst, .start_len, .stop, .busy, .done,
        .cur_src, .cur_dst, .left,
        .rd_req_valid, .rd_req_ready, .rd_req_addr, .rd_req_size, .rd_req_len, .rd_rsp_valid,
        .rd_rsp_data,
        .wr_req_valid, .wr_req_ready, .wr_req_addr, .wr_req_size, .wr_req_wdata, .wr_req_wstrb,
        .wr_req_rsp, .wr_rsp_valid);

endmodule
