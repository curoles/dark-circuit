/* Direct-mapped read-write cache (a data cache), write-through, behavioral.
 *
 * A byte address is tag | set | offset: each set holds one line of 1 << SETS_OFFSET bytes
 * (CacheValidRam, CacheTagRam, CacheDataRam, read 1 clock after the request). The protocol,
 * the write policy (write-through, no write-allocate), uncached requests and READ_ONLY are
 * CacheControl's (see there): it takes the requests, asks memory and answers; this module has
 * the line of each set and finds the hit.
 * Forwarding: a store that hits writes the data RAM at the rising edge where the next
 * request may read it; when that request is of the same set, the RAM reads the old line,
 * so the merged line is used instead.
 * invalidate=1 makes every line invalid; allowed while no load miss is served. Reset makes
 * every line invalid.
 * READ_ONLY=1 makes an instruction cache (DirectCacheRdOnly): forwarding is left out too.
 *
 *   CPU side <---> +--------------+ <---> memory side
 *                  | CacheControl |
 *                  +--------------+
 *        ram_rd, look, look_line |  ^ hit, hit_line (= line)
 *        store_write, refill,    v  |
 *        ram_wr_line, merged  +------------------------------------------+
 *                             | CacheValidRam, CacheTagRam, CacheDataRam |
 *                             | at the set; hit, forwarding              |
 *                             +------------------------------------------+
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
    output wire                  req_ready,     // uncached: follows mem_req_ready, no flop
    input  wire                  req_uncached,  // the request bypasses the lines
    input  wire [2:0]            req_size,      // uncached: 1 << req_size bytes (AXI AxSIZE)
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
    output wire [ADDR_WIDTH-1:0] mem_req_addr,  // the line's (offset 0), or an uncached request's
    output wire [2:0]            mem_req_size,  // 1 << mem_req_size bytes: the line, or uncached
    output wire [DATA_WIDTH-1:0] mem_req_wdata, // write: the line
    output wire [STRB_WIDTH-1:0] mem_req_wstrb, // write: the bytes to write
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data
);
    logic                  ram_rd;      // the RAMs read: a request taken, or a replay
    logic                  replay;      // the lookup reads its RAMs again (CacheControl)
    logic [SETS_WIDTH-1:0] rd_set;      // the set read: the request's, the lookup's on a replay
    logic                  look;        // a request taken before is looked up now (or held)
    logic [ADDR_WIDTH-1:SETS_OFFSET] look_line;  // its address without the offset in the line
    logic                  valid;       // of the set of look_line, read with the request
    logic [TAG_WIDTH-1:0]  tag;
    logic [DATA_WIDTH-1:0] ram_line;    // line of the set as the RAM read it
    logic [DATA_WIDTH-1:0] line;        // line of the set now: forwarded or ram_line
    logic                  hit;
    logic                  store_write; // a store that hits is taken by memory: write merged
    logic                  refill;      // the line from memory comes: write it
    logic                  ram_wr_en;
    logic                  fill_conflict;   // the request is at the place the refill writes
    logic [DATA_WIDTH-1:0] ram_wr_line;
    // A direct-mapped cache has no replacement state: no touch, no victim. Only forwarding
    // reads merged (none when READ_ONLY).
    /* verilator lint_off UNUSEDSIGNAL */
    logic                  load_hit;
    logic                  miss_taken;
    logic [DATA_WIDTH-1:0] merged;
    /* verilator lint_on UNUSEDSIGNAL */

    CacheControl #(.ADDR_WIDTH(ADDR_WIDTH), .SETS_OFFSET(SETS_OFFSET), .READ_ONLY(READ_ONLY))
        u_control(
            .clk, .rst_n,
            .req_valid, .req_ready, .req_uncached, .req_we, .req_addr, .req_wdata, .req_wstrb,
            .req_size, .rsp_valid, .rsp_data,
            .mem_req_valid, .mem_req_ready, .mem_req_we, .mem_req_addr, .mem_req_wdata,
            .mem_req_wstrb, .mem_req_size, .mem_rsp_valid, .mem_rsp_data,
            .ram_rd, .look, .look_line, .load_hit, .store_write, .refill, .miss_taken,
            .replay, .ram_wr_line, .merged, .hit, .hit_line(line), .fill_conflict);

    // The RAMs read the request's set, or the lookup's on a replay (CacheControl).
    assign rd_set = replay ? look_line[SETS_OFFSET +: SETS_WIDTH]
                           : req_addr[SETS_OFFSET +: SETS_WIDTH];

    // The RAMs read the set of the request; their answers come with look and hold while a
    // lookup is held (no request is taken). Refills write valid, tag and data; a store that
    // hits writes data.
    CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
        .clk, .rst_n, .invalidate,
        .rd_en(ram_rd), .rd_set(rd_set), .valid,
        .wr_en(refill), .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]), .wr_val(1'b1));

    CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
        .clk,
        .rd_en(ram_rd), .rd_set(rd_set), .tag,
        .wr_en(refill), .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]),
        .wr_tag(look_line[ADDR_WIDTH-1 -: TAG_WIDTH]));

    CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
        .clk,
        .rd_en(ram_rd), .rd_set(rd_set), .data(ram_line),
        .wr_en(ram_wr_en), .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]),
        .wr_data(ram_wr_line));

    assign hit       = look && valid && tag == look_line[ADDR_WIDTH-1 -: TAG_WIDTH];
    assign ram_wr_en = refill || store_write;

    // The request is at the place the refill writes (taken in the refill clock, CacheControl
    // replays its lookup): the same set.
    assign fill_conflict =
        req_addr[SETS_OFFSET +: SETS_WIDTH] == look_line[SETS_OFFSET +: SETS_WIDTH];

    // Forwarding needs stores; a read-only cache has none of it.
    if (READ_ONLY) begin: g_read_only
        assign line = ram_line;
    end else begin: g_store
        logic                  fwd;         // ram_line is older than a store's write
        logic [DATA_WIDTH-1:0] fwd_line;

        // Forwarding: the request taken at the edge of a store's write read the old line
        // when it is of the same set. Only the edge of a read decides: no store completes
        // while a lookup is held, and a lookup ends with its store.
        always_ff @(posedge clk)
            if (!rst_n)
                fwd <= 1'b0;
            else if (ram_rd)
                fwd <= store_write &&
                       look_line[SETS_OFFSET +: SETS_WIDTH] == req_addr[SETS_OFFSET +: SETS_WIDTH];

        always_ff @(posedge clk)
            if (store_write)
                fwd_line <= merged;

        assign line = fwd ? fwd_line : ram_line;
    end

endmodule
