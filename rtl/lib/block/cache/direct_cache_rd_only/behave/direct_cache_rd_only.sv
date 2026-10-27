/* Direct-mapped read-only cache (an instruction cache), behavioral.
 *
 * A byte address is tag | set | offset: SETS_OFFSET bits of offset in the line, SETS_WIDTH
 * bits of set index, the rest is the tag. Each set holds one line of 1 << SETS_OFFSET bytes
 * (CacheValidRam, CacheTagRam, CacheDataRam, read 1 clock after the address).
 *
 * CPU side: a request (req_en, req_addr) is taken when req_ready=1; while req_ready=0 a
 * request is ignored and the user holds it. One clock after the request the cache knows
 * whether it hits. Hit: rsp_valid=1 with the line (rsp_data), req_ready=1: a request every
 * clock while they hit. Miss: mem_req_en=1 for that clock with the address of the line
 * (offset 0), req_ready=0; the memory answers with mem_rsp_valid=1 and the line one or more
 * clocks later; in that clock rsp_valid=1 with the line from memory and the cache writes
 * valid, tag and data; req_ready=1 the clock after. invalidate=1 makes every line invalid
 * (FENCE.I); allowed while no miss is served. Reset makes every line invalid.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module DirectCacheRdOnly #(
    parameter  ADDR_WIDTH  = 32,            // byte address
    parameter  SETS_WIDTH  = 6,             // 1 << SETS_WIDTH sets
    parameter  SETS_OFFSET = 2,             // 1 << SETS_OFFSET bytes in a line (2: one word)
    localparam DATA_WIDTH  = 8 << SETS_OFFSET,
    localparam TAG_WIDTH   = ADDR_WIDTH - SETS_WIDTH - SETS_OFFSET
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  wire                  invalidate,    // all lines invalid

    // CPU side
    input  wire                  req_en,
    // The offset in the line is not used: the cache answers whole lines.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [ADDR_WIDTH-1:0] req_addr,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire                  req_ready,     // 0 while a miss is served: hold the request
    output wire                  rsp_valid,     // rsp_data is the line asked for
    output wire [DATA_WIDTH-1:0] rsp_data,

    // Memory side
    output wire                  mem_req_en,
    output wire [ADDR_WIDTH-1:0] mem_req_addr,  // address of the line (offset 0)
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data
);
    logic                  accept;      // a request is taken in this clock
    logic                  look;        // the request of the clock before is looked up now
    logic [ADDR_WIDTH-1:SETS_OFFSET] look_line;  // its address without the offset in the line
    logic                  hit;
    logic                  miss;
    logic                  waiting;     // a miss is served: the memory has not answered yet
    logic                  valid;       // of the set of look_line, read in the clock before
    logic [TAG_WIDTH-1:0]  tag;
    logic [DATA_WIDTH-1:0] data;
    logic                  refill;      // the line from memory comes: write it

    // A request is taken only when nothing waits: neither a miss found now nor one served.
    assign req_ready = !waiting && !miss;
    assign accept    = req_en && req_ready;

    always_ff @(posedge clk)
        if (!rst_n) look <= 1'b0;
        else        look <= accept;

    always_ff @(posedge clk)
        if (accept)
            look_line <= req_addr[ADDR_WIDTH-1:SETS_OFFSET];

    // The three RAMs read the set of the request; their answers come with look.
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
        .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .data,
        .wr_en(refill), .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]), .wr_data(mem_rsp_data));

    assign hit  = look && valid && tag == look_line[ADDR_WIDTH-1 -: TAG_WIDTH];
    assign miss = look && !hit;

    // A miss asks memory for its line once, in the clock it is found; the cache waits for the
    // answer, which it passes on and writes (look_line holds: no request is taken meanwhile).
    always_ff @(posedge clk)
        if (!rst_n)             waiting <= 1'b0;
        else if (miss)          waiting <= 1'b1;
        else if (mem_rsp_valid) waiting <= 1'b0;

    assign refill       = waiting && mem_rsp_valid;
    assign mem_req_en   = miss;
    assign mem_req_addr = {look_line, {SETS_OFFSET{1'b0}}};
    assign rsp_valid    = hit || refill;
    assign rsp_data     = waiting ? mem_rsp_data : data;

endmodule
