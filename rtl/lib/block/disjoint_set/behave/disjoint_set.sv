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
 * clock. The answer is offered in the clock after the last step and stays until rsp_ready:
 * rsp_root is a register, rsp_payload the payload table read at it (nothing writes the
 * table while an answer waits). req_ready is 1 only when the block is idle. Reset (and
 * DS_CLEAR) make every item its own root.
 *
 * Three tables with one write port each (and a clear of all entries): parent (a step's
 * halving, or a link), rank (a link of equal ranks), payload (DS_SET, or a link's merge).
 * The struct version has the same events, registers and write ports.
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

    // The tables.
    logic [IW-1:0]            parent  [N];
    logic [RW-1:0]            rank    [N];          // of a root: its tree's height bound
    logic [PAYLOAD_WIDTH-1:0] payload [N];          // of a root: its group's payload
    // The registers of an operation.
    state_e                   state_q;
    state_e                   state_d;
    ds_op_e                   op;
    logic [IW-1:0]            cur;                  // the item a walk is at
    logic [IW-1:0]            b;                    // DS_UNION: where the second walk starts
    logic [PAYLOAD_WIDTH-1:0] set_payload;          // DS_SET
    logic [IW-1:0]            root_a;
    logic [IW-1:0]            root_b;
    logic [IW-1:0]            out_root;             // the answer's root
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
    logic          same;                            // root_a is root_b: one group already
    logic          a_wins;                          // root_a stays the root
    logic          rank_eq;
    logic [IW-1:0] winner;
    logic [IW-1:0] loser;

    assign same    = root_a == root_b;
    assign a_wins  = rank[root_a] >= rank[root_b];
    assign rank_eq = rank[root_a] == rank[root_b];
    assign winner  = a_wins ? root_a : root_b;
    assign loser   = a_wins ? root_b : root_a;

    // The events of this clock.
    logic take;                                     // a request is taken
    logic clear;                                    // ... and it is DS_CLEAR
    logic start;                                    // ... and it is another operation
    logic step;                                     // a walk goes up
    logic done_a;                                   // the walk from a found its root
    logic to_b;                                     // ... of a union: walk from b now
    logic done_find;                                // ... of DS_FIND or DS_SET: answer
    logic set_write;                                // ... of DS_SET: write the payload
    logic done_b;                                   // the walk from b found its root
    logic link;                                     // the link clock
    logic differ;                                   // ... of two groups: link them
    logic grow;                                     // ... of equal ranks: the rank grows

    assign take      = state_q == S_IDLE && req_valid;
    assign clear     = take && req_op == DS_CLEAR;
    assign start     = take && req_op != DS_CLEAR;
    assign step      = (state_q == S_FIND_A || state_q == S_FIND_B) && !at_root;
    assign done_a    = state_q == S_FIND_A && at_root;
    assign to_b      = done_a && op == DS_UNION;
    assign done_find = done_a && op != DS_UNION;
    assign set_write = done_find && op == DS_SET;
    assign done_b    = state_q == S_FIND_B && at_root;
    assign link      = state_q == S_LINK;
    assign differ    = link && !same;
    assign grow      = differ && rank_eq;

    assign req_ready   = state_q == S_IDLE;
    assign rsp_valid   = state_q == S_RSP;
    assign rsp_root    = out_root;
    assign rsp_payload = payload[out_root];
    assign rsp_same    = out_same;
    assign merge_a     = payload[root_a];
    assign merge_b     = payload[root_b];

    // @kb: rtl/lib/block/disjoint_set/design
    always_comb begin
        state_d = state_q;
        case (state_q)
        // Takes a request; DS_CLEAR answers at once.
        S_IDLE:
            if (clear)
                state_d = S_RSP;
            else if (start)
                state_d = S_FIND_A;
        // Walks up from a; a union then walks from b.
        S_FIND_A:
            if (to_b)
                state_d = S_FIND_B;
            else if (done_find)
                state_d = S_RSP;
        // Walks up from b.
        S_FIND_B:
            if (done_b)
                state_d = S_LINK;
        // Links the roots (or finds them one).
        S_LINK:
            state_d = S_RSP;
        // Offers the answer until it is taken.
        S_RSP:
            if (rsp_ready)
                state_d = S_IDLE;
        default:
            state_d = S_IDLE;
        endcase
    end

    always_ff @(posedge clk)
        if (!rst_n)
            state_q <= S_IDLE;
        else
            state_q <= state_d;

    // The tables: reset and DS_CLEAR make every item its own root; one write each.
    always_ff @(posedge clk)
        if (!rst_n || clear)
            for (int i = 0; i < N; i++) begin
                parent[i]  <= IW'(i);
                rank[i]    <= '0;
                payload[i] <= '0;
            end
        else begin
            if (step)
                parent[cur] <= g;                   // path halving
            else if (differ)
                parent[loser] <= winner;
            if (grow)
                rank[root_a] <= rank[root_a] + 1'b1;
            if (set_write)
                payload[found] <= set_payload;
            else if (differ)
                payload[winner] <= merge;
        end

    // The registers of an operation.
    always_ff @(posedge clk) begin
        if (start) begin
            op          <= req_op;
            b           <= req_b;
            set_payload <= req_payload;
        end
        if (start)
            cur <= req_a;
        else if (step)
            cur <= g;
        else if (to_b)
            cur <= b;
        if (done_a)
            root_a <= found;
        if (done_b)
            root_b <= found;
        if (clear || done_find || link) begin
            out_root <= clear ? '0 : done_find ? found : winner;
            out_same <= link && same;
        end
    end

    // Valid/ready rule 2 on channel rsp: an answer offered and not taken stays.
    `DC_ASSERT_NEXT(a_rsp_held, rsp_valid && !rsp_ready,
                    rsp_valid && $stable({rsp_root, rsp_payload, rsp_same}))

endmodule
