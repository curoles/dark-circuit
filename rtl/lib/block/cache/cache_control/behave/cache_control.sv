/* Control of a read-write cache (write-through), behavioral: the part DirectCache,
 * SetAssocCache and SkewedCache share. The cache keeps its ways (the RAMs, hit detection,
 * forwarding, replacement) and gives this block whether the lookup hits and the line that hits.
 *
 * CPU side: requests on a valid/ready channel (AGENTS.md): a load or a store (req_we; for a
 * store req_wdata, the line with its new bytes, and req_wstrb, one bit per byte to write) is
 * taken at a rising edge with req_valid=1 and req_ready=1, and looked up in the clock after
 * (look). A load that hits answers then (rsp_valid with the line); a load that misses reads
 * its line from memory, answers with it in the clock it comes and has it written (refill). A
 * store is done when it is taken: it gets no answer.
 * Write-through, no write-allocate: every store goes to memory, from its lookup; a store that
 * hits also merges its bytes into the line that hits (merged), written when memory takes the
 * store (store_write); a store that misses leaves the cache as it is.
 * Memory side: requests on one valid/ready channel, in program order (mem_req_we, the
 * address of the line, for a write the line and its strobes), so a read sees every store
 * before it. A write gets no answer; a read is answered by mem_rsp_valid with the line one
 * or more clocks after memory took it (no ready: the cache always takes the answer). While
 * memory does not take a request, the lookup holds it (held: the cache's RAM outputs hold)
 * and req_ready is 0. A load miss is served from the clock memory takes its read
 * (miss_taken, when the cache takes its victim) until the answer comes; no request is taken
 * meanwhile, so look_line holds for the refill.
 * Uncached: a request with req_uncached=1 does not use the lines (no lookup, fill or update)
 * and passes straight to the memory side: it is taken when nothing is looked up or served, in
 * the clock memory takes it, so req_ready then follows mem_req_ready without a flop; a load is
 * answered in the clock memory answers, with memory's line. An address is used either cached
 * or uncached, never both: the cache does not check.
 * READ_ONLY=1 (an instruction cache): no stores (req_we, req_wdata and req_wstrb are not used;
 * mem_req_we, mem_req_wdata and mem_req_wstrb are 0; store_write and merged are 0), so the
 * logic only stores need is left out.
 *
 *   CPU side ---> accept, look_line (lookup) ---> the cache's ways ---> hit, hit_line ---+
 *                                                                                        |
 *   +------------------------------------------------------------------------------------+
 *   v
 *   load_hit, load_miss, store ---> memory request (store or miss, or uncached), held
 *   merged, store_write, refill, ram_wr_line ---> the cache's data RAM writes
 *   rsp_valid, rsp_data <--- hit_line, or memory's line (a served miss, an uncached read)
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module CacheControl #(
    parameter  ADDR_WIDTH  = 32,            // byte address
    parameter  SETS_OFFSET = 2,             // 1 << SETS_OFFSET bytes in a line (2: one word)
    parameter  READ_ONLY   = 0,             // 1: loads only, no store logic
    localparam DATA_WIDTH  = 8 << SETS_OFFSET,
    localparam STRB_WIDTH  = 1 << SETS_OFFSET   // a strobe per byte of the line
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low

    // CPU side: requests (a channel), answers to loads
    input  wire                  req_valid,
    output wire                  req_ready,     // uncached: follows mem_req_ready, no flop
    input  wire                  req_uncached,  // the request bypasses the lines
    // The offset in the line is not used: the cache works on whole lines. The fields of a
    // store are not used when READ_ONLY=1.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire                  req_we,        // 1: store, 0: load
    input  wire [ADDR_WIDTH-1:0] req_addr,
    input  wire [DATA_WIDTH-1:0] req_wdata,     // store: the line with its new bytes
    input  wire [STRB_WIDTH-1:0] req_wstrb,     // store: the bytes to write
    /* verilator lint_on UNUSEDSIGNAL */
    output wire                  rsp_valid,     // rsp_data is the line a load asked for
    output wire [DATA_WIDTH-1:0] rsp_data,

    // Memory side: requests (a channel), answers to reads
    output wire                  mem_req_valid,
    input  wire                  mem_req_ready,
    output wire                  mem_req_we,
    output wire [ADDR_WIDTH-1:0] mem_req_addr,  // address of the line (offset 0)
    output wire [DATA_WIDTH-1:0] mem_req_wdata, // write: the line
    output wire [STRB_WIDTH-1:0] mem_req_wstrb, // write: the bytes to write
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data,

    // The cache's ways: the lookup, and what it found
    output wire                  accept,        // a request is taken: the RAMs read it
    output logic                 look,          // a request taken before is looked up (or held)
    output logic [ADDR_WIDTH-1:SETS_OFFSET] look_line,  // its line: address without the offset
    output wire                  load_hit,      // a load hits now: replacement touch
    output wire                  store_write,   // a store that hits is taken: write merged
    output wire                  refill,        // the missed line comes: write it
    output wire                  miss_taken,    // memory takes a load miss's read: the victim
    output wire [DATA_WIDTH-1:0] ram_wr_line,   // what a data RAM write writes: refill or merged
    output wire [DATA_WIDTH-1:0] merged,        // the hit line with the store's bytes
    input  wire                  hit,           // a way hits the lookup
    input  wire [DATA_WIDTH-1:0] hit_line       // the line of the way that hits
);
    logic                  look_we;
    logic                  store;       // a store is looked up
    logic                  load_miss;
    logic                  look_req;    // the lookup asks memory: a store or a load miss
    logic                  held;        // its memory request is not taken: the lookup stays
    logic                  waiting;     // a load miss is served: memory has not answered yet
    logic                  unc_waiting; // memory took an uncached read, has not answered yet
    logic                  unc_busy;    // ... and does not answer now
    logic                  idle;        // nothing looked up or served: uncached may pass
    logic                  unc_pass;    // an uncached request goes to memory now

    // A cached request is taken only when the lookup is done: no load miss found or served,
    // memory took the lookup's own request, no uncached read waits. An uncached one passes to
    // memory when the cache is idle and is taken when memory takes it.
    // @kb: rtl/lib/block/cache/uncached
    assign unc_busy  = unc_waiting && !mem_rsp_valid;
    assign idle      = !look && !waiting && !unc_busy;
    assign unc_pass  = req_valid && req_uncached && idle;
    assign req_ready = req_uncached ? idle && mem_req_ready
                                    : !waiting && !load_miss && !held && !unc_busy;
    assign accept    = req_valid && !req_uncached && req_ready;

    always_ff @(posedge clk)
        if (!rst_n) look <= 1'b0;
        else        look <= accept || held;

    always_ff @(posedge clk)
        if (accept)
            look_line <= req_addr[ADDR_WIDTH-1:SETS_OFFSET];

    assign store     = look && look_we;
    assign load_hit  = look && !look_we && hit;
    assign load_miss = look && !look_we && !hit;

    // Write-through: a store always goes to memory; a load only when it misses. A cached
    // request comes from the lookup's registers; an uncached one straight from the CPU side
    // (only while idle: never both); valid does not depend on mem_req_ready (rule 3). The
    // fields of a write are set in the branches below.
    assign look_req      = store || load_miss;
    assign mem_req_valid = unc_pass || look_req;
    assign held          = look_req && !mem_req_ready;
    assign mem_req_addr  = unc_pass ? {req_addr[ADDR_WIDTH-1:SETS_OFFSET], {SETS_OFFSET{1'b0}}}
                                    : {look_line, {SETS_OFFSET{1'b0}}};

    // The merged line goes into the cache once: in the clock memory takes the store.
    function automatic [DATA_WIDTH-1:0] merge(input [DATA_WIDTH-1:0] old,
                                              input [DATA_WIDTH-1:0] new_bytes,
                                              input [STRB_WIDTH-1:0] strb);
        merge = old;
        for (int b = 0; b < STRB_WIDTH; b++)
            if (strb[b])
                merge[8*b +: 8] = new_bytes[8*b +: 8];
    endfunction

    // The logic only stores need; a read-only cache has none of it. Both branches drive
    // look_we, store_write, merged, ram_wr_line and the fields of a memory write (mem_req_we,
    // mem_req_wdata, mem_req_wstrb).
    // @kb: rtl/lib/block/cache/read_only
    if (READ_ONLY) begin: g_read_only
        assign look_we     = 1'b0;
        assign store_write = 1'b0;
        assign merged      = '0;
        assign ram_wr_line = mem_rsp_data;

        assign mem_req_we    = 1'b0;
        assign mem_req_wdata = '0;
        assign mem_req_wstrb = '0;
    end else begin: g_store
        logic [DATA_WIDTH-1:0] look_wdata;
        logic [STRB_WIDTH-1:0] look_wstrb;

        always_ff @(posedge clk)
            if (accept) begin
                look_we    <= req_we;
                look_wdata <= req_wdata;
                look_wstrb <= req_wstrb;
            end

        // A memory write: an uncached store as it comes, else the lookup's store.
        assign mem_req_we    = unc_pass ? req_we    : look_we;
        assign mem_req_wdata = unc_pass ? req_wdata : look_wdata;
        assign mem_req_wstrb = unc_pass ? req_wstrb : look_wstrb;

        assign merged      = merge(hit_line, look_wdata, look_wstrb);
        assign store_write = store && hit && mem_req_ready;
        assign ram_wr_line = refill ? mem_rsp_data : merged;
    end

    // A load miss is served from the clock memory takes its read until the answer comes
    // (look_line holds: no request is taken meanwhile).
    assign miss_taken = load_miss && mem_req_ready;

    always_ff @(posedge clk)
        if (!rst_n)             waiting <= 1'b0;
        else if (miss_taken)    waiting <= 1'b1;
        else if (mem_rsp_valid) waiting <= 1'b0;

    assign refill = waiting && mem_rsp_valid;

    // A lookup ends when memory takes its read, and no request is taken while the miss is
    // served: so a refill never meets a store's write, and the refill writes look_line's
    // place in the cache.
    `DC_ASSERT(a_no_look_while_waiting, !(look && waiting))

    // A lookup whose memory request is not taken offers it again, unchanged, in the next
    // clock (held: the lookup and the RAM outputs stay). Not uncached requests: they
    // follow the CPU side, which may withdraw (kb rtl/lib/block/cache/uncached).
    `DC_ASSERT_NEXT(a_look_req_held, look_req && !mem_req_ready,
                    look_req && $stable(mem_req_addr) && $stable(mem_req_we) &&
                    (!mem_req_we || ($stable(mem_req_wdata) && $stable(mem_req_wstrb))))

    // An uncached read is served from the clock memory takes it until the answer comes; its
    // line is not written into the cache.
    always_ff @(posedge clk)
        if (!rst_n)                                        unc_waiting <= 1'b0;
        else if (unc_pass && mem_req_ready && !mem_req_we) unc_waiting <= 1'b1;
        else if (mem_rsp_valid)                            unc_waiting <= 1'b0;

    // It passed while idle, and nothing is taken while it waits: alone with memory.
    `DC_ASSERT(a_unc_alone, !(unc_waiting && (look || waiting)))

    assign rsp_valid = load_hit || refill || (unc_waiting && mem_rsp_valid);
    assign rsp_data  = (waiting || unc_waiting) ? mem_rsp_data : hit_line;

endmodule
