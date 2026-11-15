/* Disjoint set (union-find), behavioral: N items in groups that only merge, each group named
 * by one of its items (its root) and carrying a payload; one operation at a time.
 *
 * Every item has a parent in its group; a root is its own parent, so a group is a tree and
 * its root names it: two items are in one group when they have the same root. Operations
 * (DisjointSetPkg::ds_op_e) come on channel req and answer on channel rsp:
 * - DS_FIND a: rsp_root the root of a's group, rsp_payload the group's payload;
 * - DS_UNION a, b: the two groups become one; rsp_same is 1 when they already were (nothing
 *   changes), else the new root is one of the two roots and the group's payload is merge;
 * - DS_SET a: the payload of a's group := req_payload (answers it, with the root);
 * - DS_CLEAR: every item its own group, every payload 0 (answers root 0, payload 0).
 * The payload is the user's: the block keeps it per group and never looks inside. Only the
 * user knows how two payloads combine (a size adds, an odd count XORs, a flag ORs), so in
 * the clock a union links two groups, merge_a and merge_b are their payloads (a's group and
 * b's) and merge, a combinational function of those two, is the merged payload kept.
 *
 * For example, N = 6, payload a count of members (merge = merge_a + merge_b), after
 * DS_SET 0..5 to 1:
 *   DS_UNION 0, 1   rsp_root 0, payload 2, same 0
 *   DS_UNION 1, 2   rsp_root 0, payload 3
 *   DS_UNION 3, 4   rsp_root 3, payload 2
 *   DS_FIND 2       rsp_root 0, payload 3
 *   DS_UNION 4, 0   rsp_root 3, payload 5   (both ranks 1: a's root, 3, stays the root)
 *   DS_UNION 2, 3   rsp_root 3, payload 5, same 1
 *
 * Union by rank: the root of the lower tree (rank, an upper bound of its height) goes under
 * the other; equal ranks, a's root stays root and its rank grows. So a tree is at most
 * log2(N) high. Find walks up from the item with path halving: every item it passes is
 * pointed at its grandparent, so later walks are shorter; a clock reads the parent and the
 * grandparent, two levels a clock. A union finds a's root, then b's, then links them in one
 * clock. The answer is offered in the clock after the last step and stays until rsp_ready;
 * req_ready is 1 only when the block is idle (no answer offered or pending). Reset (and
 * DS_CLEAR) make every item its own root.
 *
 *   req --> find a --> (union) find b --> link (merge) --> rsp
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

    typedef enum logic [2:0] {
        S_IDLE,                                     // takes a request
        S_FIND_A,                                   // walks up from a
        S_FIND_B,                                   // walks up from b
        S_LINK,                                     // links the two roots
        S_RSP                                       // offers the answer
    } state_e;

    logic [IW-1:0]            parent  [N];
    logic [RW-1:0]            rank    [N];          // of a root: its tree's height bound
    logic [PAYLOAD_WIDTH-1:0] payload [N];          // of a root: its group's payload
    state_e                   state;
    ds_op_e                   op;
    logic [IW-1:0]            cur;                  // the item a walk is at
    logic [IW-1:0]            b;                    // DS_UNION: where the second walk starts
    logic [IW-1:0]            root_a;
    logic [IW-1:0]            root_b;
    logic [PAYLOAD_WIDTH-1:0] set_payload;          // DS_SET
    logic [IW-1:0]            out_root;             // the answer
    logic [PAYLOAD_WIDTH-1:0] out_payload;
    logic                     out_same;

    // One step of a walk at cur: its parent p and grandparent g. cur is the root when p is
    // cur, p is when g is p; else cur's parent becomes g and the walk goes on at g.
    logic [IW-1:0] p;
    logic [IW-1:0] g;
    logic          at_root;                         // the root is found in this clock
    logic [IW-1:0] found;                           // the root, when at_root

    assign p       = parent[cur];
    assign g       = parent[p];
    assign at_root = p == cur || g == p;
    assign found   = (p == cur) ? cur : p;

    // The link: the root of the lower rank goes under the other; equal ranks, a's root
    // stays and its rank grows.
    logic          a_wins;                          // root_a stays the root
    assign a_wins  = rank[root_a] >= rank[root_b];

    assign req_ready   = state == S_IDLE;
    assign rsp_valid   = state == S_RSP;
    assign rsp_root    = out_root;
    assign rsp_payload = out_payload;
    assign rsp_same    = out_same;
    assign merge_a     = payload[root_a];
    assign merge_b     = payload[root_b];

    // @kb: rtl/lib/block/disjoint_set/design
    always_ff @(posedge clk)
        if (!rst_n) begin
            for (int i = 0; i < N; i++) begin
                parent[i]  <= IW'(i);
                rank[i]    <= '0;
                payload[i] <= '0;
            end
            state <= S_IDLE;
        end else if (state == S_IDLE && req_valid && req_op == DS_CLEAR) begin
            for (int i = 0; i < N; i++) begin
                parent[i]  <= IW'(i);
                rank[i]    <= '0;
                payload[i] <= '0;
            end
            out_root    <= '0;
            out_payload <= '0;
            out_same    <= 1'b0;
            state       <= S_RSP;
        end else
            case (state)
            S_IDLE:
                if (req_valid) begin
                    op          <= req_op;
                    cur         <= req_a;
                    b           <= req_b;
                    set_payload <= req_payload;
                    state       <= S_FIND_A;
                end
            S_FIND_A, S_FIND_B:
                if (!at_root) begin
                    parent[cur] <= g;                       // path halving
                    cur         <= g;
                end else if (state == S_FIND_A && op == DS_UNION) begin
                    root_a <= found;
                    cur    <= b;
                    state  <= S_FIND_B;
                end else if (state == S_FIND_B) begin
                    root_b <= found;
                    state  <= S_LINK;
                end else begin                              // DS_FIND, DS_SET
                    out_root    <= found;
                    out_payload <= op == DS_SET ? set_payload : payload[found];
                    out_same    <= 1'b0;
                    if (op == DS_SET)
                        payload[found] <= set_payload;
                    state <= S_RSP;
                end
            S_LINK: begin
                out_same <= root_a == root_b;
                if (root_a == root_b) begin
                    out_root    <= root_a;
                    out_payload <= payload[root_a];
                end else begin
                    out_root    <= a_wins ? root_a : root_b;
                    out_payload <= merge;
                    if (a_wins) begin
                        parent[root_b]  <= root_a;
                        payload[root_a] <= merge;
                        if (rank[root_a] == rank[root_b])
                            rank[root_a] <= rank[root_a] + 1'b1;
                    end else begin
                        parent[root_a]  <= root_b;
                        payload[root_b] <= merge;
                    end
                end
                state <= S_RSP;
            end
            S_RSP:
                if (rsp_ready)
                    state <= S_IDLE;
            default:
                state <= S_IDLE;
            endcase

    // Valid/ready rule 2 on channel rsp: an answer offered and not taken stays.
    `DC_ASSERT_NEXT(a_rsp_held, rsp_valid && !rsp_ready,
                    rsp_valid && $stable({rsp_root, rsp_payload, rsp_same}))

endmodule
