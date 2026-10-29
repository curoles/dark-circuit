/* Arbiter between the memory sides of an instruction cache and a data cache, and one memory,
 * made of blocks and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there). Gates: the tie is
 * decided by prio (two CmpEq), else by POLICY (generate: a constant side, or round-robin with
 * a flip-flop of the side served last, which only round-robin has); muxes select the side
 * presented, held while memory does not take it (two flip-flops: the hold and its side); a
 * Fifo keeps the sides of the reads in memory.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module InsnDataCacheArbiter import CachePkg::*; #(
    parameter  ADDR_WIDTH    = 32,                  // byte address
    parameter  DATA_WIDTH    = 32,                  // a line
    parameter  POLICY        = ARB_ROUND_ROBIN,     // when both want memory and prio is none
    parameter  PENDING_WIDTH = 1,                   // 1 << PENDING_WIDTH reads in memory at most
    localparam STRB_WIDTH    = DATA_WIDTH / 8
)(
    input  wire                  clk,
    input  wire                  rst_n,             // synchronous reset, active low
    input  wire [1:0]            prio,              // PRIO_NONE, PRIO_DATA or PRIO_INSN

    // Instruction cache, its memory side: reads only
    input  wire                  icache_req_valid,
    output wire                  icache_req_ready,
    input  wire [ADDR_WIDTH-1:0] icache_req_addr,
    output wire                  icache_rsp_valid,
    output wire [DATA_WIDTH-1:0] icache_rsp_data,

    // Data cache, its memory side
    input  wire                  dcache_req_valid,
    output wire                  dcache_req_ready,
    input  wire                  dcache_req_we,
    input  wire [ADDR_WIDTH-1:0] dcache_req_addr,
    input  wire [DATA_WIDTH-1:0] dcache_req_wdata,
    input  wire [STRB_WIDTH-1:0] dcache_req_wstrb,
    output wire                  dcache_rsp_valid,
    output wire [DATA_WIDTH-1:0] dcache_rsp_data,

    // Memory
    output wire                  mem_req_valid,
    input  wire                  mem_req_ready,
    output wire                  mem_req_we,
    output wire [ADDR_WIDTH-1:0] mem_req_addr,
    output wire [DATA_WIDTH-1:0] mem_req_wdata,     // write: the line
    output wire [STRB_WIDTH-1:0] mem_req_wstrb,     // write: the bytes to write
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data
);
    `DC_STATIC_ASSERT(a_policy_known,
        POLICY == ARB_DATA_FIRST || POLICY == ARB_INSN_FIRST || POLICY == ARB_ROUND_ROBIN)
    `DC_STATIC_ASSERT(a_line_of_bytes, DATA_WIDTH % 8 == 0)

    // A side is a bit: 0 the instruction cache, 1 the data cache.
    wire hold_q;        // the request presented in the clock before was not taken: it stays
    wire side_q;        // its side
    wire full;          // the queue of reads in memory: no room for one more
    wire full_n;
    wire empty;
    wire owner;         // the side of the oldest read in memory: its answer goes there
    wire owner_n;
    wire prio_d;        // prio says the data cache
    wire prio_i;        // prio says the instruction cache
    wire prio_i_n;
    wire policy_d;      // POLICY says the data cache
    wire policy_by_i;   // POLICY says the data cache and prio does not say the instruction one
    wire tie_d;         // the data cache wins a tie
    wire write_or_room; // the data cache's request can go: a write, or room for a read
    wire i_ok;          // the instruction cache asks, and its read can go
    wire d_ok;          // the data cache asks, and its request can go
    wire both;
    wire free_side;     // the side when nothing is held
    wire side;          // the side presented to memory
    wire side_n;
    wire ready_n;
    wire not_taken;
    wire taken;         // memory takes the request
    wire we_n;
    wire taken_read;
    // Status the arbiter does not need.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [PENDING_WIDTH:0] count;
    wire almost_full;
    wire almost_empty;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/cache/insn_data_cache_arbiter/design
    // The tie: prio first (PRIO_DATA and PRIO_INSN never hold together), else POLICY. The
    // package name is needed: Icarus takes an imported name alone as a port expression for an
    // implicit wire.
    CmpEq #(2) u_cmp_eq_prio_d(.in1(prio), .in2(CachePkg::PRIO_DATA), .eq(prio_d));
    CmpEq #(2) u_cmp_eq_prio_i(.in1(prio), .in2(CachePkg::PRIO_INSN), .eq(prio_i));
    generate
    if (POLICY == ARB_DATA_FIRST) begin: g_data_first
        assign policy_d = 1'b1;
    end else if (POLICY == ARB_INSN_FIRST) begin: g_insn_first
        assign policy_d = 1'b0;
    end else begin: g_round_robin
        // The side memory took the last request from; the instruction cache first after reset.
        wire last_q;
        DffSyncRstEn #(.WIDTH(1), .RST_VAL(1'b1)) u_dff_sync_rst_en_last(
            .clk, .rst_n, .en(taken), .in(side), .out(last_q));
        Inv  #(1) u_inv(.in(last_q), .out(policy_d));    // not the side served last
    end
    endgenerate
    Inv  #(1) u_inv_prio_i (.in(prio_i), .out(prio_i_n));
    And2 #(1) u_and2_policy(.in1(prio_i_n), .in2(policy_d), .out(policy_by_i));
    Or2  #(1) u_or2_tie    (.in1(prio_d), .in2(policy_by_i), .out(tie_d));

    // A read goes only while the queue has room.
    Inv  #(1) u_inv_full   (.in(full), .out(full_n));
    And2 #(1) u_and2_i_ok  (.in1(icache_req_valid), .in2(full_n), .out(i_ok));
    Or2  #(1) u_or2_d_room (.in1(dcache_req_we), .in2(full_n), .out(write_or_room));
    And2 #(1) u_and2_d_ok  (.in1(dcache_req_valid), .in2(write_or_room), .out(d_ok));

    // The side: the held one, else the tie's winner when both ask, else the one that asks.
    And2 #(1) u_and2_both  (.in1(i_ok), .in2(d_ok), .out(both));
    Mux2 #(1) u_mux2_free  (.in0(d_ok), .in1(tie_d), .sel(both), .out(free_side));
    Mux2 #(1) u_mux2_side  (.in0(free_side), .in1(side_q), .sel(hold_q), .out(side));
    Inv  #(1) u_inv_side   (.in(side), .out(side_n));

    Mux2 #(1) u_mux2_valid (.in0(i_ok), .in1(d_ok), .sel(side), .out(mem_req_valid));
    And2 #(1) u_and2_we    (.in1(side), .in2(dcache_req_we), .out(mem_req_we));
    Mux2 #(ADDR_WIDTH) u_mux2_addr(.in0(icache_req_addr), .in1(dcache_req_addr), .sel(side),
                                   .out(mem_req_addr));
    assign mem_req_wdata = dcache_req_wdata;    // a write is always the data cache's
    assign mem_req_wstrb = dcache_req_wstrb;

    And2 #(1) u_and2_taken (.in1(mem_req_valid), .in2(mem_req_ready), .out(taken));
    And3 #(1) u_and3_i_rdy (.in1(mem_req_ready), .in2(side_n), .in3(i_ok),
                            .out(icache_req_ready));
    And3 #(1) u_and3_d_rdy (.in1(mem_req_ready), .in2(side), .in3(d_ok),
                            .out(dcache_req_ready));

    // The hold and its side.
    Inv  #(1) u_inv_ready  (.in(mem_req_ready), .out(ready_n));
    And2 #(1) u_and2_hold  (.in1(mem_req_valid), .in2(ready_n), .out(not_taken));
    DffSyncRst #(.WIDTH(1), .RST_VAL(1'b0)) u_dff_sync_rst_hold(
        .clk, .rst_n, .in(not_taken), .out(hold_q));
    DffSyncRst #(.WIDTH(1), .RST_VAL(1'b0)) u_dff_sync_rst_side(
        .clk, .rst_n, .in(side), .out(side_q));

    // Sides of the reads in memory, oldest first (the we of the side presented).
    Inv  #(1) u_inv_we     (.in(mem_req_we), .out(we_n));
    And2 #(1) u_and2_read  (.in1(taken), .in2(we_n), .out(taken_read));
    Fifo #(.ADDR_WIDTH(PENDING_WIDTH), .DATA_WIDTH(1)) u_fifo(
        .clk, .rst_n, .write(taken_read), .data_in(side), .read(mem_rsp_valid),
        .data_out(owner), .empty, .full, .count, .almost_full, .almost_empty);

    Inv  #(1) u_inv_owner  (.in(owner), .out(owner_n));
    And2 #(1) u_and2_rsp_i (.in1(mem_rsp_valid), .in2(owner_n), .out(icache_rsp_valid));
    And2 #(1) u_and2_rsp_d (.in1(mem_rsp_valid), .in2(owner), .out(dcache_rsp_valid));
    assign icache_rsp_data = mem_rsp_data;
    assign dcache_rsp_data = mem_rsp_data;

    `DC_ASSERT(a_answer_expected, !mem_rsp_valid || !empty)
    `DC_ASSERT(a_prio_known, prio != 2'd3)

endmodule
