/* Direct-mapped read-write cache (a data cache), write-through, behavioral.
 *
 * A byte address is tag | set | offset, as in DirectCacheRdOnly: each set holds one line of
 * 1 << SETS_OFFSET bytes (CacheValidRam, CacheTagRam, CacheDataRam, read 1 clock after the
 * request).
 *
 * CPU side: requests on a valid/ready channel (AGENTS.md): a load or a store (req_we; for a
 * store req_wdata, the line with its new bytes, and req_wstrb, one bit per byte to write) is
 * taken at a rising edge with req_valid=1 and req_ready=1, and looked up in the clock after.
 * A load that hits answers then (rsp_valid with the line); a load that misses reads its line
 * from memory, answers with it in the clock it comes and writes it. A store is done when it
 * is taken: it gets no answer.
 * Write-through, no write-allocate: every store goes to memory, from its lookup; a store that
 * hits also merges its bytes into the line, written when memory takes the store; a store
 * that misses leaves the cache as it is.
 * Memory side: requests on one valid/ready channel, in program order (mem_req_we, the
 * address of the line, for a write the line and its strobes), so a read sees every store
 * before it. A write gets no answer; a read is answered by mem_rsp_valid with the line one
 * or more clocks after memory took it (no ready: the cache always takes the answer). While
 * memory does not take a request, the lookup holds it and req_ready is 0.
 * Forwarding: a store that hits writes the data RAM at the rising edge where the next
 * request may read it; when that request is of the same set, the RAM reads the old line,
 * so the merged line is used instead.
 * invalidate=1 makes every line invalid; allowed while no load miss is served. Reset makes
 * every line invalid.
 * READ_ONLY=1 makes an instruction cache (DirectCacheRdOnly): no stores (req_we, req_wdata
 * and req_wstrb are not used; mem_req_we, mem_req_wdata and mem_req_wstrb are 0), so the
 * logic only stores need (their fields of the request, the merge, forwarding) is left out.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DirectCache #(
    parameter  ADDR_WIDTH  = 32,            // byte address
    parameter  SETS_WIDTH  = 6,             // 1 << SETS_WIDTH sets
    parameter  SETS_OFFSET = 2,             // 1 << SETS_OFFSET bytes in a line (2: one word)
    parameter  READ_ONLY   = 0,             // 1: loads only, no store logic
    localparam DATA_WIDTH  = 8 << SETS_OFFSET,
    localparam STRB_WIDTH  = 1 << SETS_OFFSET,  // a strobe per byte of the line
    localparam TAG_WIDTH   = ADDR_WIDTH - SETS_WIDTH - SETS_OFFSET
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  wire                  invalidate,    // all lines invalid

    // CPU side: requests (a channel), answers to loads
    input  wire                  req_valid,
    output wire                  req_ready,
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
    input  wire [DATA_WIDTH-1:0] mem_rsp_data
);
    logic                  accept;      // a request is taken in this clock
    logic                  look;        // a request taken before is looked up now (or held)
    logic [ADDR_WIDTH-1:SETS_OFFSET] look_line;  // its address without the offset in the line
    logic                  look_we;
    logic [DATA_WIDTH-1:0] look_wdata;
    logic [STRB_WIDTH-1:0] look_wstrb;
    logic                  valid;       // of the set of look_line, read with the request
    logic [TAG_WIDTH-1:0]  tag;
    logic [DATA_WIDTH-1:0] ram_line;    // line of the set as the RAM read it
    logic [DATA_WIDTH-1:0] line;        // line of the set now: forwarded or ram_line
    logic                  hit;
    logic                  store;       // a store is looked up
    logic                  load_hit;
    logic                  load_miss;
    logic                  held;        // its memory request is not taken: the lookup stays
    logic                  store_write; // a store that hits is taken by memory: write merged
    logic                  waiting;     // a load miss is served: memory has not answered yet
    logic                  refill;      // the line from memory comes: write it
    logic                  ram_wr_en;
    logic [DATA_WIDTH-1:0] ram_wr_line;

    // A request is taken only when the lookup is done: no load miss found or served, and
    // memory took the lookup's own request.
    assign req_ready = !waiting && !load_miss && !held;
    assign accept    = req_valid && req_ready;

    always_ff @(posedge clk)
        if (!rst_n) look <= 1'b0;
        else        look <= accept || held;

    always_ff @(posedge clk)
        if (accept)
            look_line <= req_addr[ADDR_WIDTH-1:SETS_OFFSET];

    // The RAMs read the set of the request; their answers come with look and hold while a
    // lookup is held (no request is taken). Refills write valid, tag and data; a store that
    // hits writes data.
    CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
        .clk, .rst_n, .invalidate,
        .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .valid,
        .wr_en(refill), .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]), .wr_val(1'b1));

    CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
        .clk,
        .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .tag,
        .wr_en(refill), .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]),
        .wr_tag(look_line[ADDR_WIDTH-1 -: TAG_WIDTH]));

    CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
        .clk,
        .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .data(ram_line),
        .wr_en(ram_wr_en), .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]),
        .wr_data(ram_wr_line));

    assign hit       = look && valid && tag == look_line[ADDR_WIDTH-1 -: TAG_WIDTH];
    assign store     = look && look_we;
    assign load_hit  = look && !look_we && hit;
    assign load_miss = look && !look_we && !hit;

    // Write-through: a store always goes to memory; a load only when it misses. The request
    // comes from the lookup's registers, so valid does not depend on any input (rule 3).
    assign mem_req_valid = store || load_miss;
    assign held          = mem_req_valid && !mem_req_ready;
    assign mem_req_we    = look_we;
    assign mem_req_addr  = {look_line, {SETS_OFFSET{1'b0}}};
    assign mem_req_wdata = look_wdata;
    assign mem_req_wstrb = look_wstrb;

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
    // look_we, look_wdata, look_wstrb, store_write, ram_wr_line and line.
    // @kb: rtl/lib/block/cache/read_only
    if (READ_ONLY) begin: g_read_only
        assign look_we     = 1'b0;
        assign look_wdata  = '0;
        assign look_wstrb  = '0;
        assign store_write = 1'b0;
        assign ram_wr_line = mem_rsp_data;
        assign line        = ram_line;
    end else begin: g_store
        logic                  fwd;         // ram_line is older than a store's write
        logic [DATA_WIDTH-1:0] fwd_line;
        logic [DATA_WIDTH-1:0] merged;      // line with the bytes of the store

        always_ff @(posedge clk)
            if (accept) begin
                look_we    <= req_we;
                look_wdata <= req_wdata;
                look_wstrb <= req_wstrb;
            end

        assign merged      = merge(line, look_wdata, look_wstrb);
        assign store_write = store && hit && mem_req_ready;
        assign ram_wr_line = refill ? mem_rsp_data : merged;

        // Forwarding: the request taken at the edge of a store's write read the old line
        // when it is of the same set. Only the edge of a read decides: no store completes
        // while a lookup is held, and a lookup ends with its store.
        always_ff @(posedge clk)
            if (!rst_n)
                fwd <= 1'b0;
            else if (accept)
                fwd <= store_write &&
                       look_line[SETS_OFFSET +: SETS_WIDTH] == req_addr[SETS_OFFSET +: SETS_WIDTH];

        always_ff @(posedge clk)
            if (store_write)
                fwd_line <= merged;

        assign line = fwd ? fwd_line : ram_line;
    end

    // A load miss is served from the clock memory takes its read until the answer comes
    // (look_line holds: no request is taken meanwhile).
    always_ff @(posedge clk)
        if (!rst_n)                          waiting <= 1'b0;
        else if (load_miss && mem_req_ready) waiting <= 1'b1;
        else if (mem_rsp_valid)              waiting <= 1'b0;

    assign refill = waiting && mem_rsp_valid;

    // A lookup ends when memory takes its read, and no request is taken while the miss is
    // served: so a refill (while waiting) never meets a store's write (in a lookup) on the
    // data RAM's one write port, and the refill writes the set of look_line.
    `DC_ASSERT(a_no_look_while_waiting, !(look && waiting))

    assign ram_wr_en = refill || store_write;

    assign rsp_valid = load_hit || refill;
    assign rsp_data  = waiting ? mem_rsp_data : line;

endmodule
