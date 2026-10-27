/* Stack (last in, first out) for small depths, made of blocks and gates.
 *
 * Same ports and behavior as the behave version (see there): push, pop, both (replace the
 * top), a pop ignored when empty, a push when full ignored or with OVERWRITE=1 overwriting
 * the oldest entry.
 *
 * The entries are a RegFile with one write and one combinational read port: the read port
 * reads the top entry (data_out), the write port writes data_in at top (replace) or at
 * top + 1 (push). top and count are DffSyncRst with Mux2 in front: +1 on a push (count only
 * when not full), -1 on a pop, else hold; +1 is Incr, -1 is NOT(Incr(NOT x)), since
 * x - 1 = ~(~x + 1). empty is NorReduce of count, full is CmpEq of count with DEPTH.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Stack #(
    parameter  ADDR_WIDTH = 3,                  // 1 << ADDR_WIDTH entries
    parameter  DATA_WIDTH = 8,
    parameter  OVERWRITE  = 0,                  // 1: a push when full overwrites the oldest
    localparam DEPTH      = 1 << ADDR_WIDTH
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  wire                  push,          // ignored when full, unless OVERWRITE=1
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire                  pop,           // ignored when empty
    output wire [DATA_WIDTH-1:0] data_out,      // top entry, valid when empty is 0
    output wire                  empty,
    output wire                  full,
    output wire [ADDR_WIDTH:0]   count          // 0..DEPTH entries
);
    localparam [ADDR_WIDTH:0] FULL_COUNT = (ADDR_WIDTH+1)'(DEPTH);

    wire [ADDR_WIDTH-1:0] top;          // index of the top entry
    wire [ADDR_WIDTH-1:0] top_inc;      // top + 1: the entry a push writes
    wire [ADDR_WIDTH-1:0] top_dec;      // top - 1: the top after a pop
    wire [ADDR_WIDTH-1:0] top_n;
    wire [ADDR_WIDTH-1:0] top_n_inc;
    wire [ADDR_WIDTH-1:0] top_popped;   // top after a pop, or held
    wire [ADDR_WIDTH-1:0] top_next;
    wire [ADDR_WIDTH:0]   count_inc;
    wire [ADDR_WIDTH:0]   count_dec;
    wire [ADDR_WIDTH:0]   count_n;
    wire [ADDR_WIDTH:0]   count_n_inc;
    wire [ADDR_WIDTH:0]   count_popped;
    wire [ADDR_WIDTH:0]   count_next;
    // Carry outs of the incrementers: the counters wrap only where the stack wraps.
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  co_top_inc;
    wire                  co_top_dec;
    wire                  co_count_inc;
    wire                  co_count_dec;
    /* verilator lint_on UNUSEDSIGNAL */
    wire                  empty_n;
    wire                  full_n;
    wire                  push_n;
    wire                  push_ok;      // a push may add an entry: not full, or OVERWRITE
    wire                  replace;      // push and pop of a stack with entries: new top
    wire                  replace_n;
    wire                  do_push;      // a new entry above the top
    wire                  do_pop;
    wire                  grow;         // a push that adds to the count (not full)
    wire                  wr_en;
    wire [ADDR_WIDTH-1:0] wr_addr;

    NorReduce #(ADDR_WIDTH+1) u_nor_reduce(.in(count), .out(empty));
    CmpEq     #(ADDR_WIDTH+1) u_cmp_eq(.in1(count), .in2(FULL_COUNT), .eq(full));
    Inv #(1) u_inv_empty(.in(empty), .out(empty_n));
    Inv #(1) u_inv_full (.in(full), .out(full_n));
    Inv #(1) u_inv_push (.in(push), .out(push_n));

    if (OVERWRITE != 0) begin: g_overwrite
        assign push_ok = 1'b1;
    end else begin: g_keep
        assign push_ok = full_n;
    end

    And3 #(1) u_and3_replace(.in1(push), .in2(pop), .in3(empty_n), .out(replace));
    Inv  #(1) u_inv_replace (.in(replace), .out(replace_n));
    And3 #(1) u_and3_push   (.in1(push), .in2(replace_n), .in3(push_ok), .out(do_push));
    And3 #(1) u_and3_pop    (.in1(pop), .in2(push_n), .in3(empty_n), .out(do_pop));
    And2 #(1) u_and2_grow   (.in1(do_push), .in2(full_n), .out(grow));

    // top: +1 on a push, -1 on a pop.
    Incr #(.WIDTH(ADDR_WIDTH), .GROUP(ADDR_WIDTH)) u_incr_top(.in(top), .out(top_inc),
                                                               .co(co_top_inc));
    Inv  #(ADDR_WIDTH) u_inv_top(.in(top), .out(top_n));
    Incr #(.WIDTH(ADDR_WIDTH), .GROUP(ADDR_WIDTH)) u_incr_top_n(.in(top_n), .out(top_n_inc),
                                                                 .co(co_top_dec));
    Inv  #(ADDR_WIDTH) u_inv_top_dec(.in(top_n_inc), .out(top_dec));
    Mux2 #(ADDR_WIDTH) u_mux2_top_pop (.in0(top), .in1(top_dec), .sel(do_pop), .out(top_popped));
    Mux2 #(ADDR_WIDTH) u_mux2_top_push(.in0(top_popped), .in1(top_inc), .sel(do_push),
                                       .out(top_next));
    DffSyncRst #(.WIDTH(ADDR_WIDTH)) u_dff_sync_rst_top(.clk(clk), .rst_n(rst_n), .in(top_next),
                                                        .out(top));

    // count: +1 on a push when not full, -1 on a pop.
    Incr #(.WIDTH(ADDR_WIDTH+1), .GROUP(ADDR_WIDTH+1)) u_incr_count(.in(count), .out(count_inc),
                                                                   .co(co_count_inc));
    Inv  #(ADDR_WIDTH+1) u_inv_count(.in(count), .out(count_n));
    Incr #(.WIDTH(ADDR_WIDTH+1), .GROUP(ADDR_WIDTH+1)) u_incr_count_n(.in(count_n),
                                                                     .out(count_n_inc),
                                                                     .co(co_count_dec));
    Inv  #(ADDR_WIDTH+1) u_inv_count_dec(.in(count_n_inc), .out(count_dec));
    Mux2 #(ADDR_WIDTH+1) u_mux2_count_pop (.in0(count), .in1(count_dec), .sel(do_pop),
                                           .out(count_popped));
    Mux2 #(ADDR_WIDTH+1) u_mux2_count_push(.in0(count_popped), .in1(count_inc), .sel(grow),
                                           .out(count_next));
    DffSyncRst #(.WIDTH(ADDR_WIDTH+1)) u_dff_sync_rst_count(.clk(clk), .rst_n(rst_n),
                                                            .in(count_next), .out(count));

    // Entries: a replace writes the top, a push the entry above it.
    Or2  #(1)          u_or2_wr  (.in1(replace), .in2(do_push), .out(wr_en));
    Mux2 #(ADDR_WIDTH) u_mux2_wr (.in0(top), .in1(top_inc), .sel(do_push), .out(wr_addr));
    RegFile #(.RD_PORTS(1), .WR_PORTS(1), .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
        u_reg_file(.clk(clk), .rd_addr(top), .rd_data(data_out), .wr_en(wr_en),
                   .wr_addr(wr_addr), .wr_data(data_in));

endmodule
