/* Direct-mapped read-write cache (a data cache), write-through, made of blocks and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there; the protocol, the
 * write policy, uncached requests and READ_ONLY are CacheControl's). The RAMs are the struct
 * CacheValidRam, CacheTagRam and CacheDataRam. Then:
 *   hit       = look AND valid AND (tag == tag of look_line)
 *   data RAM write: refill OR store_write, of CacheControl's ram_wr_line
 *   fwd       = DffSyncRstEn(en ram_rd) of store_write AND (set == set of the request)
 *   fwd_line  = DffEn (store_write) of merged
 *   line      = Mux2(ram_line, fwd_line, fwd), CacheControl's hit_line
 * (READ_ONLY=1: line = ram_line, no forwarding).
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
    input  wire                  req_uncached_dbg_bypass,   // debug/test mode: straight to
                                                            // memory, no lookup
    input  wire [2:0]            req_size,      // 1 << req_size bytes (AXI AxSIZE): bypass,
                                                // no cache
    input  wire                  req_nocache,   // the address may not be cached (a
                                                // device's): looked up, never filled
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
    localparam LINE_WIDTH = ADDR_WIDTH - SETS_OFFSET;   // address bits above the offset

    wire                  ram_rd;       // the RAMs read: a request taken, or a replay
    wire                  replay;       // the lookup reads its RAMs again (CacheControl)
    wire [SETS_WIDTH-1:0] rd_set;       // the set read: the request's, the lookup's on a replay
    wire                  look;         // a request taken before is looked up now (or held)
    wire [LINE_WIDTH-1:0] look_line;    // its address without the offset in the line
    wire                  valid;        // of the set of look_line, read with the request
    wire [TAG_WIDTH-1:0]  tag;
    wire                  tag_eq;
    wire [DATA_WIDTH-1:0] ram_line;     // line of the set as the RAM read it
    wire [DATA_WIDTH-1:0] line;         // line of the set now: forwarded or ram_line
    wire                  hit;
    wire                  store_write;  // a store that hits is taken by memory: write merged
    wire                  refill;       // the line from memory comes: write it
    wire                  ram_wr_en;
    wire                  same_set;     // the request is of the lookup's set
    wire [DATA_WIDTH-1:0] ram_wr_line;
    // A direct-mapped cache has no replacement state: no touch, no victim. Only forwarding
    // reads merged (none when READ_ONLY).
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  load_hit;
    wire                  miss_taken;
    wire [DATA_WIDTH-1:0] merged;
    /* verilator lint_on UNUSEDSIGNAL */

    CacheControl #(.ADDR_WIDTH(ADDR_WIDTH), .SETS_OFFSET(SETS_OFFSET), .READ_ONLY(READ_ONLY))
        u_control(
            .clk, .rst_n,
            .req_valid, .req_ready, .req_uncached_dbg_bypass,
            .req_we, .req_addr, .req_wdata, .req_wstrb,
            .req_size, .req_nocache, .rsp_valid, .rsp_data,
            .mem_req_valid, .mem_req_ready, .mem_req_we, .mem_req_addr, .mem_req_wdata,
            .mem_req_wstrb, .mem_req_size, .mem_rsp_valid, .mem_rsp_data,
            .ram_rd, .look, .look_line, .load_hit, .store_write, .refill, .miss_taken,
            .replay, .ram_wr_line, .merged, .hit, .hit_line(line), .fill_conflict(same_set));

    // The RAMs read the request's set, or the lookup's on a replay (CacheControl).
    Mux2 #(SETS_WIDTH) u_mux2_rd_set(.in0(req_addr[SETS_OFFSET +: SETS_WIDTH]),
                                     .in1(look_line[SETS_WIDTH-1:0]), .sel(replay), .out(rd_set));

    CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
        .clk, .rst_n, .invalidate,
        .rd_en(ram_rd), .rd_set(rd_set), .valid,
        .wr_en(refill), .wr_set(look_line[SETS_WIDTH-1:0]), .wr_val(1'b1));

    CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
        .clk,
        .rd_en(ram_rd), .rd_set(rd_set), .tag,
        .wr_en(refill), .wr_set(look_line[SETS_WIDTH-1:0]),
        .wr_tag(look_line[LINE_WIDTH-1:SETS_WIDTH]));

    Or2 #(1) u_or2_ram_wr(.in1(refill), .in2(store_write), .out(ram_wr_en));
    CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
        .clk,
        .rd_en(ram_rd), .rd_set(rd_set), .data(ram_line),
        .wr_en(ram_wr_en), .wr_set(look_line[SETS_WIDTH-1:0]), .wr_data(ram_wr_line));

    CmpEq #(TAG_WIDTH) u_cmp_eq_tag(.in1(tag), .in2(look_line[LINE_WIDTH-1:SETS_WIDTH]),
                                    .eq(tag_eq));
    And3 #(1) u_and3_hit(.in1(look), .in2(valid), .in3(tag_eq), .out(hit));

    // The request is of the lookup's set: CacheControl's fill_conflict (taken in the refill
    // clock, its lookup is replayed), and forwarding.
    CmpEq #(SETS_WIDTH) u_cmp_eq_set(.in1(look_line[SETS_WIDTH-1:0]),
                                     .in2(req_addr[SETS_OFFSET +: SETS_WIDTH]), .eq(same_set));

    // Forwarding needs stores; a read-only cache has none of it.
    if (READ_ONLY) begin: g_read_only
        assign line = ram_line;
    end else begin: g_store
        wire                  fwd_new;      // the request taken at a store's write, same set
        wire                  fwd;          // ram_line is older than a store's write
        wire [DATA_WIDTH-1:0] fwd_line;

        // Forwarding (see the behave version): decided at the edge of a read.
        And2  #(1) u_and2_fwd (.in1(store_write), .in2(same_set), .out(fwd_new));
        DffSyncRstEn #(.WIDTH(1)) u_dff_sync_rst_en_fwd(.clk, .rst_n, .en(ram_rd), .in(fwd_new),
                                                        .out(fwd));
        DffEn #(DATA_WIDTH) u_dff_en_fwd_line(.clk, .en(store_write), .in(merged), .out(fwd_line));
        Mux2 #(DATA_WIDTH) u_mux2_line_fwd(.in0(ram_line), .in1(fwd_line), .sel(fwd),
                                           .out(line));
    end

endmodule
