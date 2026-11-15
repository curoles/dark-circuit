/* Disjoint set (union-find): N items in groups that only merge, each group named by one of
 * its items (its root) and carrying a payload; one operation at a time; made of blocks,
 * parts and gates.
 *
 * Same ports, behavior, events, registers and write ports as the behave version (see
 * there). The state is one-hot, five flops (idle, find a, find b, link, answer). Each table
 * entry is a DffSyncRstEn whose reset value is the entry's start (parent i, rank 0,
 * payload 0), reset by rst_n or DS_CLEAR, written through a Decoder of its table's write
 * address; reads are MuxNs. A walk's step: p = parent[cur], g = parent[p] (two MuxNs in a
 * row), at_root = (p == cur) | (g == p) (CmpEq), found = p == cur ? cur : p (Mux2). The
 * link: a_wins = rank[root_a] >= rank[root_b] (CmpGe), the winner and the loser (Mux2), the
 * rank of a's root + 1 when equal (CmpEq, Incr).
 *
 *   parent[] --MuxN (cur)--> p --MuxN (p)--> g --CmpEq--> at_root, found
 *   rank[] --MuxN (root_a, root_b)--> CmpGe, CmpEq --> winner, loser, grow
 *   payload[] --MuxN (root_a, root_b)--> merge_a, merge_b; --MuxN (rsp_root)--> rsp_payload
 *   write ports: parent (step: cur := g; link: loser := winner), rank (grow: root_a += 1),
 *                payload (DS_SET: found := set_payload; link: winner := merge)
 *   registers: op, b, set_payload (start); cur (start, step, to_b); root_a, root_b;
 *              rsp_root, rsp_same (clear, done_find, link)
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module DisjointSet import DisjointSetPkg::*; #(
    parameter  N             = 16,                  // items, 2 or more
    parameter  PAYLOAD_WIDTH = 8,                   // bits of a group's payload
    localparam IW            = $clog2(N)            // bits of an item
)(
    input  wire                     clk,
    input  wire                     rst_n,          // synchronous reset, active low
    // Channel req: an operation.
    input  wire                     req_valid,
    output wire                     req_ready,
    input  ds_op_e                  req_op,
    input  wire [IW-1:0]            req_a,
    input  wire [IW-1:0]            req_b,          // DS_UNION
    input  wire [PAYLOAD_WIDTH-1:0] req_payload,    // DS_SET
    // Channel rsp: its answer.
    output wire                     rsp_valid,
    input  wire                     rsp_ready,
    output wire [IW-1:0]            rsp_root,       // the root of the group (a's; the union's)
    output wire [PAYLOAD_WIDTH-1:0] rsp_payload,    // the group's payload
    output wire                     rsp_same,       // DS_UNION: a and b were in one group
    // The merge of a union, in the clock it links: merge = f(merge_a, merge_b).
    output wire [PAYLOAD_WIDTH-1:0] merge_a,        // the payload of a's group
    output wire [PAYLOAD_WIDTH-1:0] merge_b,        // the payload of b's group
    input  wire [PAYLOAD_WIDTH-1:0] merge           // the merged payload, from the user
);
    `DC_STATIC_ASSERT(a_sizes, N >= 2 && PAYLOAD_WIDTH >= 1)

    localparam RW = $clog2(IW + 1);                 // bits of a rank, 0..log2(N)
    localparam PW = PAYLOAD_WIDTH;

    // The state, one-hot.
    wire [4:0] state;                               // {rsp, link, find_b, find_a, idle}
    wire idle, find_a, find_b, link, rsp;
    wire idle_next, find_a_next, find_b_next, rsp_next;
    // The tables and their write ports.
    wire [N-1:0][IW-1:0] parent;
    wire [N-1:0][RW-1:0] rank;
    wire [N-1:0][PW-1:0] payload;
    wire                 keep_n;                    // rst_n & ~clear: the entries' reset
    wire                 par_we;
    wire [IW-1:0]        par_waddr;
    wire [IW-1:0]        par_wdata;
    wire [IW-1:0]        pay_waddr;
    wire [PW-1:0]        pay_wdata;
    wire                 pay_we;
    wire [RW-1:0]        rank_inc;                  // rank[root_a] + 1
    // The table's last write enables are not used when N is not a power of 2.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [(1<<IW)-1:0]   par_en;
    wire [(1<<IW)-1:0]   rank_en;
    wire [(1<<IW)-1:0]   pay_en;
    wire                 rank_co;                   // a rank never reaches 2^RW
    /* verilator lint_on UNUSEDSIGNAL */
    // The registers of an operation.
    wire [1:0]           op;
    wire [IW-1:0]        b;
    wire [PW-1:0]        set_payload;
    wire [IW-1:0]        cur;
    wire [IW-1:0]        cur_next;
    wire [IW-1:0]        root_a;
    wire [IW-1:0]        root_b;
    wire [IW-1:0]        out_root;
    wire [IW-1:0]        out_root_next;
    // A walk and the link.
    wire [IW-1:0]        p;
    wire [IW-1:0]        g;
    wire                 p_is_cur;
    wire                 g_is_p;
    wire                 at_root;
    wire                 at_root_n;
    wire [IW-1:0]        found;
    wire [RW-1:0]        rank_a;
    wire [RW-1:0]        rank_b;
    wire                 same;
    wire                 same_n;
    wire                 a_wins;
    wire                 rank_eq;
    wire [IW-1:0]        winner;
    wire [IW-1:0]        loser;
    // The events of this clock.
    wire                 is_clear_req, is_clear_req_n, is_union, is_union_n, is_set;
    wire                 take, clear, clear_n, start, step_a, step_b, step;
    wire                 done_a, to_b, done_find, set_write, done_b, differ, grow;
    wire                 req_valid_n, rsp_ready_n, idle_stay, rsp_done, answer, cur_en, link_same;

    // @kb: rtl/lib/block/disjoint_set/design
    // The events. The package name is needed: Icarus takes an imported name alone as a port
    // expression for an implicit wire.
    CmpEq #(2) u_cmp_eq_clear(.in1(req_op), .in2(DisjointSetPkg::DS_CLEAR), .eq(is_clear_req));
    CmpEq #(2) u_cmp_eq_union(.in1(op), .in2(DisjointSetPkg::DS_UNION), .eq(is_union));
    CmpEq #(2) u_cmp_eq_set(.in1(op), .in2(DisjointSetPkg::DS_SET), .eq(is_set));
    Inv  #(1) u_inv_clear_req(.in(is_clear_req), .out(is_clear_req_n));
    Inv  #(1) u_inv_union(.in(is_union), .out(is_union_n));
    Inv  #(1) u_inv_at_root(.in(at_root), .out(at_root_n));
    Inv  #(1) u_inv_same(.in(same), .out(same_n));
    And2 #(1) u_and2_take(.in1(idle), .in2(req_valid), .out(take));
    And2 #(1) u_and2_clear(.in1(take), .in2(is_clear_req), .out(clear));
    And2 #(1) u_and2_start(.in1(take), .in2(is_clear_req_n), .out(start));
    And2 #(1) u_and2_step_a(.in1(find_a), .in2(at_root_n), .out(step_a));
    And2 #(1) u_and2_step_b(.in1(find_b), .in2(at_root_n), .out(step_b));
    Or2  #(1) u_or2_step(.in1(step_a), .in2(step_b), .out(step));
    And2 #(1) u_and2_done_a(.in1(find_a), .in2(at_root), .out(done_a));
    And2 #(1) u_and2_to_b(.in1(done_a), .in2(is_union), .out(to_b));
    And2 #(1) u_and2_done_find(.in1(done_a), .in2(is_union_n), .out(done_find));
    And2 #(1) u_and2_set_write(.in1(done_find), .in2(is_set), .out(set_write));
    And2 #(1) u_and2_done_b(.in1(find_b), .in2(at_root), .out(done_b));
    And2 #(1) u_and2_differ(.in1(link), .in2(same_n), .out(differ));
    And2 #(1) u_and2_grow(.in1(differ), .in2(rank_eq), .out(grow));

    // The state: idle (reset), find a, find b, link, answer.
    Inv  #(1) u_inv_req_valid(.in(req_valid), .out(req_valid_n));
    Inv  #(1) u_inv_rsp_ready(.in(rsp_ready), .out(rsp_ready_n));
    And2 #(1) u_and2_idle_stay(.in1(idle), .in2(req_valid_n), .out(idle_stay));
    And2 #(1) u_and2_rsp_done(.in1(rsp), .in2(rsp_ready), .out(rsp_done));
    Or2  #(1) u_or2_idle(.in1(idle_stay), .in2(rsp_done), .out(idle_next));
    Ao21 #(1) u_ao21_find_a(.in1(find_a), .in2(at_root_n), .in3(start), .out(find_a_next));
    Ao21 #(1) u_ao21_find_b(.in1(find_b), .in2(at_root_n), .in3(to_b), .out(find_b_next));
    Or3  #(1) u_or3_answer(.in1(clear), .in2(done_find), .in3(link), .out(answer));
    Ao21 #(1) u_ao21_rsp(.in1(rsp), .in2(rsp_ready_n), .in3(answer), .out(rsp_next));
    DffSyncRst #(.WIDTH(5), .RST_VAL(5'b00001)) u_dff_sync_rst_state(
        .clk, .rst_n, .in({rsp_next, done_b, find_b_next, find_a_next, idle_next}),
        .out(state));
    assign {rsp, link, find_b, find_a, idle} = state;
    assign req_ready = idle;
    assign rsp_valid = rsp;

    // A walk: the parent and the grandparent of cur.
    MuxN #(.N(N), .WIDTH(IW)) u_mux_n_p(.in(parent), .sel(cur), .out(p));
    MuxN #(.N(N), .WIDTH(IW)) u_mux_n_g(.in(parent), .sel(p), .out(g));
    CmpEq #(IW) u_cmp_eq_p(.in1(p), .in2(cur), .eq(p_is_cur));
    CmpEq #(IW) u_cmp_eq_g(.in1(g), .in2(p), .eq(g_is_p));
    Or2  #(1) u_or2_at_root(.in1(p_is_cur), .in2(g_is_p), .out(at_root));
    Mux2 #(IW) u_mux2_found(.in0(p), .in1(cur), .sel(p_is_cur), .out(found));

    // The link: the root of the lower rank under the other; equal ranks, a's root stays.
    MuxN #(.N(N), .WIDTH(RW)) u_mux_n_rank_a(.in(rank), .sel(root_a), .out(rank_a));
    MuxN #(.N(N), .WIDTH(RW)) u_mux_n_rank_b(.in(rank), .sel(root_b), .out(rank_b));
    CmpEq #(IW) u_cmp_eq_same(.in1(root_a), .in2(root_b), .eq(same));
    CmpGe #(RW) u_cmp_ge_rank(.in1(rank_a), .in2(rank_b), .ge(a_wins));
    CmpEq #(RW) u_cmp_eq_rank(.in1(rank_a), .in2(rank_b), .eq(rank_eq));
    Mux2 #(IW) u_mux2_winner(.in0(root_b), .in1(root_a), .sel(a_wins), .out(winner));
    Mux2 #(IW) u_mux2_loser(.in0(root_a), .in1(root_b), .sel(a_wins), .out(loser));

    // The tables: an entry resets to its start with rst_n or DS_CLEAR.
    Inv  #(1) u_inv_clear(.in(clear), .out(clear_n));
    And2 #(1) u_and2_keep(.in1(rst_n), .in2(clear_n), .out(keep_n));
    Or2  #(1) u_or2_par_we(.in1(step), .in2(differ), .out(par_we));
    Mux2 #(IW) u_mux2_par_waddr(.in0(loser), .in1(cur), .sel(step), .out(par_waddr));
    Mux2 #(IW) u_mux2_par_wdata(.in0(winner), .in1(g), .sel(step), .out(par_wdata));
    Decoder #(IW) u_decoder_par(.in(par_waddr), .en(par_we), .out(par_en));
    Incr #(.WIDTH(RW)) u_incr_rank(.in(rank_a), .out(rank_inc), .co(rank_co));
    Decoder #(IW) u_decoder_rank(.in(root_a), .en(grow), .out(rank_en));
    Or2  #(1) u_or2_pay_we(.in1(set_write), .in2(differ), .out(pay_we));
    Mux2 #(IW) u_mux2_pay_waddr(.in0(winner), .in1(found), .sel(set_write), .out(pay_waddr));
    Mux2 #(PW) u_mux2_pay_wdata(.in0(merge), .in1(set_payload), .sel(set_write),
                                .out(pay_wdata));
    Decoder #(IW) u_decoder_pay(.in(pay_waddr), .en(pay_we), .out(pay_en));
    for (genvar i = 0; i < N; i++) begin : g_entry
        DffSyncRstEn #(.WIDTH(IW), .RST_VAL(IW'(i))) u_dff_sync_rst_en_parent(
            .clk, .rst_n(keep_n), .en(par_en[i]), .in(par_wdata), .out(parent[i]));
        DffSyncRstEn #(.WIDTH(RW)) u_dff_sync_rst_en_rank(
            .clk, .rst_n(keep_n), .en(rank_en[i]), .in(rank_inc), .out(rank[i]));
        DffSyncRstEn #(.WIDTH(PW)) u_dff_sync_rst_en_payload(
            .clk, .rst_n(keep_n), .en(pay_en[i]), .in(pay_wdata), .out(payload[i]));
    end
    MuxN #(.N(N), .WIDTH(PW)) u_mux_n_merge_a(.in(payload), .sel(root_a), .out(merge_a));
    MuxN #(.N(N), .WIDTH(PW)) u_mux_n_merge_b(.in(payload), .sel(root_b), .out(merge_b));
    MuxN #(.N(N), .WIDTH(PW)) u_mux_n_rsp(.in(payload), .sel(out_root), .out(rsp_payload));

    // The registers of an operation.
    DffEn #(2 + IW + PW) u_dff_en_req(.clk, .en(start), .in({req_op, req_b, req_payload}),
                                      .out({op, b, set_payload}));
    Or3  #(1) u_or3_cur_en(.in1(start), .in2(step), .in3(to_b), .out(cur_en));
    Mux1hot3 #(IW) u_mux1hot3_cur(.in0(req_a), .in1(g), .in2(b), .sel({to_b, step, start}),
                                  .out(cur_next));
    DffEn #(IW) u_dff_en_cur(.clk, .en(cur_en), .in(cur_next), .out(cur));
    DffEn #(IW) u_dff_en_root_a(.clk, .en(done_a), .in(found), .out(root_a));
    DffEn #(IW) u_dff_en_root_b(.clk, .en(done_b), .in(found), .out(root_b));
    Mux1hot3 #(IW) u_mux1hot3_out_root(.in0(IW'(0)), .in1(found), .in2(winner),
                                       .sel({link, done_find, clear}), .out(out_root_next));
    DffEn #(IW) u_dff_en_out_root(.clk, .en(answer), .in(out_root_next), .out(out_root));
    And2 #(1) u_and2_link_same(.in1(link), .in2(same), .out(link_same));
    DffEn #(1) u_dff_en_out_same(.clk, .en(answer), .in(link_same), .out(rsp_same));
    assign rsp_root = out_root;

    // On a named vector: Icarus 13 misevaluates $onehot of a concatenation.
    `DC_ASSERT(a_state_one_hot, $onehot(state))
    // Valid/ready rule 2 on channel rsp: an answer offered and not taken stays.
    `DC_ASSERT_NEXT(a_rsp_held, rsp_valid && !rsp_ready,
                    rsp_valid && $stable({rsp_root, rsp_payload, rsp_same}))

endmodule
