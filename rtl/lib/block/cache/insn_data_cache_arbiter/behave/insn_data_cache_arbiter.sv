/* Arbiter between the memory sides of an instruction cache and a data cache, and one memory,
 * behavioral.
 *
 * All three ports are the memory side of the caches (DirectCacheRdOnly, DirectCache, ...):
 * requests on a valid/ready channel, taken at a rising edge with valid=1 and ready=1; a read
 * is answered by rsp_valid with the line one or more clocks after memory took it (no ready);
 * a write gets no answer. The instruction cache only reads. One request at a time goes to
 * memory:
 * - Who: a side that wants memory alone gets it. When both want it, prio decides
 *   (PRIO_DATA, PRIO_INSN, CachePkg), and with PRIO_NONE the parameter POLICY:
 *   ARB_DATA_FIRST, ARB_INSN_FIRST or ARB_ROUND_ROBIN (the side memory did not take the last
 *   request from; the instruction cache first after reset).
 * - A request presented to memory and not taken stays until memory takes it, whatever prio
 *   and the other side do: its fields do not change under memory.
 * - Answers: memory answers reads in order. A queue (Fifo) keeps the side of every read
 *   memory took and has not answered, and the answer goes to that side; while the queue is
 *   full no read is presented (a write is).
 * Order between the two caches is not kept: a store and a later fetch of its address are
 * ordered by software (FENCE.I).
 * Each side's request goes through a FlowThroughBuffer first (u_icache_flow,
 * u_dcache_flow): a cache's ready is "its buffer is empty", a flip-flop, so neither cache
 * sees memory's ready or the other cache's valid without one. Without the cut one side's
 * valid decides the other side's ready, and through a CPU's stall that ready can come back
 * into the first valid: a loop (kb pattern rtl/lib/block/flow_through_buffer/design). A
 * request flows through in the clock memory takes it at once; else its buffer keeps it and
 * the logic below presents it, held as before. So a cache's request is taken by its buffer
 * (its answer comes later) while the other side holds memory.
 *
 *   icache_req --> FlowThroughBuffer --> i_* --+
 *                                              +--> side (hold, prio, POLICY) --> mem_req
 *   dcache_req --> FlowThroughBuffer --> d_* --+
 *   mem_rsp --> owner: the Fifo of the sides of the reads --> icache_rsp or dcache_rsp
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module InsnDataCacheArbiter import CachePkg::*, AtomicPkg::*; #(
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
    input  wire [2:0]            icache_req_size,   // 1 << size bytes (AXI AxSIZE)
    output wire                  icache_rsp_valid,
    output wire [DATA_WIDTH-1:0] icache_rsp_data,

    // Data cache, its memory side
    input  wire                  dcache_req_valid,
    output wire                  dcache_req_ready,
    input  wire                  dcache_req_we,
    input  wire [ADDR_WIDTH-1:0] dcache_req_addr,
    input  wire [2:0]            dcache_req_size,   // 1 << size bytes (AXI AxSIZE)
    input  atop_t                dcache_req_atop,   // ATOP_NONE, or an atomic (a read)
    input  cmo_t                 dcache_req_cmo,    // CMO_NONE, or a CBO (a write)
    input  wire [DATA_WIDTH-1:0] dcache_req_wdata,
    input  wire [STRB_WIDTH-1:0] dcache_req_wstrb,
    output wire                  dcache_rsp_valid,
    output wire [DATA_WIDTH-1:0] dcache_rsp_data,

    // Memory
    output wire                  mem_req_valid,
    input  wire                  mem_req_ready,
    output wire                  mem_req_we,
    output wire [ADDR_WIDTH-1:0] mem_req_addr,
    output wire [2:0]            mem_req_size,      // 1 << size bytes (AXI AxSIZE)
    output atop_t                mem_req_atop,      // the data cache's; ATOP_NONE for the
    output cmo_t                 mem_req_cmo,       // the data cache's; CMO_NONE for the
                                                    // instruction cache's
                                                    // instruction cache
    output wire [DATA_WIDTH-1:0] mem_req_wdata,     // write: the line
    output wire [STRB_WIDTH-1:0] mem_req_wstrb,     // write: the bytes to write
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data
);
    `DC_STATIC_ASSERT(a_policy_known,
        POLICY == ARB_DATA_FIRST || POLICY == ARB_INSN_FIRST || POLICY == ARB_ROUND_ROBIN)
    `DC_STATIC_ASSERT(a_line_of_bytes, DATA_WIDTH % 8 == 0)

    localparam logic SIDE_I = 1'b0;
    localparam logic SIDE_D = 1'b1;

    logic hold_q;   // the request presented in the clock before was not taken: it stays
    logic side_q;   // its side
    logic last_q;   // the side memory took the last request from
    logic i_ok;     // the instruction cache asks, and its read can go
    logic d_ok;     // the data cache asks, and its request can go
    logic side;     // the side presented to memory
    logic taken;    // memory takes the request
    wire  full;     // the queue of reads in memory: no room for one more
    wire  empty;
    wire  owner;    // the side of the oldest read in memory: its answer goes there
    // Status the arbiter does not need.
    /* verilator lint_off UNUSEDSIGNAL */
    wire  [PENDING_WIDTH:0] count;
    wire  almost_full;
    wire  almost_empty;
    /* verilator lint_on UNUSEDSIGNAL */

    // Each side's request goes through a flow-through buffer: the cache's ready comes from a
    // flop (its buffer is empty), never from memory's ready or the other cache's valid.
    localparam I_REQ_WIDTH = ADDR_WIDTH + 3;    // {addr, size}
    localparam D_REQ_WIDTH = 1 + ADDR_WIDTH + 3 + $bits(atop_t) + $bits(cmo_t) + DATA_WIDTH +
                             STRB_WIDTH;        // {we, addr, size, atop, cmo, wdata, wstrb}
    typedef logic [I_REQ_WIDTH-1:0] i_req_t;
    typedef logic [D_REQ_WIDTH-1:0] d_req_t;

    wire                  i_valid;      // the instruction cache's request, behind its buffer
    wire                  i_ready;
    wire [ADDR_WIDTH-1:0] i_addr;
    wire [2:0]            i_size;
    wire                  d_valid;      // the data cache's request, behind its buffer
    wire                  d_ready;
    wire                  d_we;
    wire [ADDR_WIDTH-1:0] d_addr;
    wire [2:0]            d_size;
    atop_t                d_atop;
    cmo_t                 d_cmo;
    wire [DATA_WIDTH-1:0] d_wdata;
    wire [STRB_WIDTH-1:0] d_wstrb;

    // @kb: rtl/lib/block/flow_through_buffer/design
    FlowThroughBufferT #(.T(i_req_t)) u_icache_flow(
        .clk, .rst_n,
        .in_valid(icache_req_valid), .in_ready(icache_req_ready),
        .in_data({icache_req_addr, icache_req_size}),
        .out_valid(i_valid), .out_ready(i_ready), .out_data({i_addr, i_size}));
    FlowThroughBufferT #(.T(d_req_t)) u_dcache_flow(
        .clk, .rst_n,
        .in_valid(dcache_req_valid), .in_ready(dcache_req_ready),
        .in_data({dcache_req_we, dcache_req_addr, dcache_req_size, dcache_req_atop, dcache_req_cmo,
                  dcache_req_wdata, dcache_req_wstrb}),
        .out_valid(d_valid), .out_ready(d_ready),
        .out_data({d_we, d_addr, d_size, d_atop, d_cmo, d_wdata, d_wstrb}));

    // @kb: rtl/lib/block/cache/insn_data_cache_arbiter/design
    // The side that gets memory when both want it: prio, else POLICY. The only place that
    // decides between the sides (a generic arbiter would take it over).
    function automatic logic tie_winner(input logic [1:0] p, input logic last);
        if (p == PRIO_DATA) return SIDE_D;
        if (p == PRIO_INSN) return SIDE_I;
        case (POLICY)
            ARB_DATA_FIRST: return SIDE_D;
            ARB_INSN_FIRST: return SIDE_I;
            default:        return !last;   // ARB_ROUND_ROBIN
        endcase
    endfunction

    // A read goes only while the queue has room for its side.
    assign i_ok = i_valid && !full;
    assign d_ok = d_valid && (d_we || !full);

    always_comb
        if (hold_q)
            side = side_q;
        else if (i_ok && d_ok)
            side = tie_winner(prio, last_q);
        else
            side = d_ok ? SIDE_D : SIDE_I;

    assign mem_req_valid = (side == SIDE_D) ? d_ok : i_ok;
    assign mem_req_we    = (side == SIDE_D) && d_we;
    assign mem_req_addr  = (side == SIDE_D) ? d_addr : i_addr;
    assign mem_req_size  = (side == SIDE_D) ? d_size : i_size;
    // @kb: rtl/lib/block/cache/atomic
    assign mem_req_atop  = (side == SIDE_D) ? d_atop : ATOP_NONE;
    // @kb: rtl/lib/block/cache/cbo
    assign mem_req_cmo   = (side == SIDE_D) ? d_cmo  : CMO_NONE;
    assign mem_req_wdata = d_wdata;             // a write, an atomic: the data cache's
    assign mem_req_wstrb = d_wstrb;

    assign taken            = mem_req_valid && mem_req_ready;
    assign i_ready = mem_req_ready && side == SIDE_I && i_ok;
    assign d_ready = mem_req_ready && side == SIDE_D && d_ok;

    always_ff @(posedge clk)
        if (!rst_n) begin
            hold_q <= 1'b0;
            side_q <= SIDE_I;
            last_q <= SIDE_D;
        end else begin
            hold_q <= mem_req_valid && !mem_req_ready;
            side_q <= side;
            if (taken)
                last_q <= side;
        end

    // Sides of the reads in memory, oldest first.
    Fifo #(.ADDR_WIDTH(PENDING_WIDTH), .DATA_WIDTH(1)) u_fifo(
        .clk, .rst_n, .write(taken && !mem_req_we), .data_in(side), .read(mem_rsp_valid),
        .data_out(owner), .empty, .full, .count, .almost_full, .almost_empty);

    assign icache_rsp_valid = mem_rsp_valid && owner == SIDE_I;
    assign dcache_rsp_valid = mem_rsp_valid && owner == SIDE_D;
    assign icache_rsp_data  = mem_rsp_data;
    assign dcache_rsp_data  = mem_rsp_data;

    // A request presented to memory and not taken stays, its fields unchanged (the caches
    // keep theirs, rule 2; a plain read's wdata and wstrb mean nothing, an atomic's are
    // its operand).
    `DC_ASSERT_NEXT(a_mem_req_held, mem_req_valid && !mem_req_ready,
                    mem_req_valid && $stable(mem_req_we) && $stable(mem_req_addr) &&
                    $stable(mem_req_atop) && $stable(mem_req_cmo) &&
                    ((!mem_req_we && !is_atomic(mem_req_atop)) ||
                     ($stable(mem_req_wdata) && $stable(mem_req_wstrb))))

    `DC_ASSERT(a_answer_expected, !mem_rsp_valid || !empty)
    `DC_ASSERT(a_prio_known, prio != 2'd3)

endmodule
