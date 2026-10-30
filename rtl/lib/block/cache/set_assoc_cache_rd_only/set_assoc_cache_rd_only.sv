/* Set-associative read-only cache (an instruction cache): SetAssocCache with READ_ONLY=1.
 *
 * Same ports and protocol as DirectCacheRdOnly (see there): a request is taken at a rising
 * edge with req_ready=1; a hit answers one clock later; a miss asks memory for the line
 * (held until memory takes it), answers with the line from memory and writes it;
 * invalidate=1 makes every line invalid (allowed while no miss is served). Each set has WAYS
 * lines; a miss replaces the way CacheReplacement picks when memory takes the read
 * (REPLACEMENT, CachePkg: REPL_LRU, REPL_RANDOM; invalid ways first); a hit and a fill touch
 * their way. See SetAssocCache.
 * One file for the behave and the struct library: the SetAssocCache of the library it is
 * built with gives the version.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

module SetAssocCacheRdOnly import CachePkg::*; #(
    parameter  ADDR_WIDTH  = 32,            // byte address
    parameter  SETS_WIDTH  = 6,             // 1 << SETS_WIDTH sets
    parameter  SETS_OFFSET = 2,             // 1 << SETS_OFFSET bytes in a line (2: one word)
    parameter  WAYS        = 4,             // lines in a set, at least 2
    parameter  REPLACEMENT = REPL_LRU,      // CachePkg: REPL_LRU, REPL_RANDOM
    localparam DATA_WIDTH  = 8 << SETS_OFFSET,
    localparam STRB_WIDTH  = 1 << SETS_OFFSET
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  wire                  invalidate,    // all lines invalid

    // CPU side
    input  wire                  req_valid,
    input  wire [ADDR_WIDTH-1:0] req_addr,
    output wire                  req_ready,     // 0 while a miss is served: hold the request
    output wire                  rsp_valid,     // rsp_data is the line asked for
    output wire [DATA_WIDTH-1:0] rsp_data,

    // Memory side
    output wire                  mem_req_valid,
    input  wire                  mem_req_ready,
    output wire [ADDR_WIDTH-1:0] mem_req_addr,  // address of the line (offset 0)
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data
);
    // A read-only cache writes nothing to memory: these are always 0.
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  mem_req_we;
    wire [DATA_WIDTH-1:0] mem_req_wdata;
    wire [STRB_WIDTH-1:0] mem_req_wstrb;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/cache/read_only
    SetAssocCache #(.ADDR_WIDTH(ADDR_WIDTH), .SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET),
                    .WAYS(WAYS), .REPLACEMENT(REPLACEMENT), .READ_ONLY(1)) u_set_assoc_cache(
        .clk, .rst_n, .invalidate,
        .req_valid, .req_ready, .req_we(1'b0), .req_addr, .req_wdata({DATA_WIDTH{1'b0}}),
        .req_wstrb({STRB_WIDTH{1'b0}}), .rsp_valid, .rsp_data,
        .mem_req_valid, .mem_req_ready, .mem_req_we, .mem_req_addr, .mem_req_wdata,
        .mem_req_wstrb, .mem_rsp_valid, .mem_rsp_data);

endmodule
