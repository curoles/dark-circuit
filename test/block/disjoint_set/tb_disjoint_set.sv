/* Test of DisjointSetT (DisjointSet behind it), behave or struct version.
 *
 * The payload is a struct of a member count (merged by adding), an odd bit (XOR) and a flag
 * (OR), so that a wrong merge or a merge of the wrong groups shows. Requests come from a
 * SimVldRdySource and answers go to a SimVldRdySink, both stalling at random: random
 * operations (unions, finds, sets, a clear in the middle and now and then) on N = 2, 5, 16,
 * 64 items (64 on Verilator only), 3000 on Verilator, 300 on Icarus. Model: a group label
 * per item, a union relabels a whole group (no trees), unlike the block. Every answer is
 * checked: the payload of the item's group (model), rsp_same, and the root, which stays the
 * group's root until a union, which must keep one of its two groups' roots (root); after a
 * clear every item is its own root. Every answer must come within 2 log2(N) + 6 clocks of
 * its request (latency). In the end every kind must have happened (a union of two groups of
 * 2 or more from N = 4 up). Checks named with DC_TEST_FAIL: model, root, latency, cover.
 * Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbDisjointSetCheck #(
    parameter N = 16
)(
    input  wire  clk,
    output logic done
);
    import DisjointSetPkg::*;

`ifdef VERILATOR
    localparam N_OPS = 3000;
`else
    localparam N_OPS = 300;
`endif
    localparam IW      = $clog2(N);
    localparam LATENCY = 2 * IW + 6;

    typedef struct packed {
        logic [7:0] count;              // members: merged by adding
        logic       odd;                // merged by XOR
        logic       flag;               // merged by OR
    } payload_t;

    typedef struct packed {
        ds_op_e        op;
        logic [IW-1:0] a;
        logic [IW-1:0] b;
        payload_t      payload;
    } req_t;

    typedef struct packed {
        logic [IW-1:0] root;
        payload_t      payload;
        logic          same;
    } rsp_t;

    // The channels carry plain vectors: Icarus 13 has no queues of structs.
    typedef logic [$bits(req_t)-1:0] req_v;
    typedef logic [$bits(rsp_t)-1:0] rsp_v;

    logic          rst_n;
    wire           req_valid;
    wire           req_ready;
    req_v          req_bits;
    req_t          req;
    wire           rsp_valid;
    wire           rsp_ready;
    wire [IW-1:0]  rsp_root;
    payload_t      rsp_payload;
    wire           rsp_same;
    rsp_v          rsp_bits;
    payload_t      merge_a;
    payload_t      merge_b;
    payload_t      merge;
    req_v          ops [$];             // every request, in order
    integer        seed;

    SimVldRdySource #(.T(req_v)) u_source(
        .clk, .rst_n, .out_valid(req_valid), .out_ready(req_ready), .out_data(req_bits));
    SimVldRdySink #(.T(rsp_v)) u_sink(
        .clk, .rst_n, .in_valid(rsp_valid), .in_ready(rsp_ready), .in_data(rsp_bits));

    assign req      = req_t'(req_bits);
    assign rsp_bits = {rsp_root, rsp_payload, rsp_same};

    DisjointSetT #(.N(N), .T(payload_t)) u_disjoint_set(
        .clk, .rst_n, .req_valid, .req_ready, .req_op(req.op), .req_a(req.a), .req_b(req.b),
        .req_payload(req.payload), .rsp_valid, .rsp_ready, .rsp_root, .rsp_payload, .rsp_same,
        .merge_a, .merge_b, .merge);

    // The user's merge.
    function automatic payload_t merged(payload_t x, payload_t y);
        return {x.count + y.count, x.odd ^ y.odd, x.flag | y.flag};
    endfunction

    assign merge = merged(merge_a, merge_b);

    // Latency: clocks from a request's transfer to its answer.
    logic busy;                         // a request taken, its answer not offered yet
    int   waited;
    always @(posedge clk)
        if (!rst_n) begin
            busy   <= 1'b0;
            waited <= 0;
        end else if (req_valid && req_ready) begin
            busy   <= 1'b1;
            waited <= 1;
        end else if (busy && rsp_valid)
            busy <= 1'b0;
        else if (busy) begin
            waited <= waited + 1;
            if (waited > LATENCY)
                `DC_TEST_FAIL(latency, $sformatf("N=%0d: no answer %0d clocks after a request",
                                                 N, waited))
        end

    // The model: label[i] the group of item i, its payload, and its root (every item its own
    // root after a clear; a union names the new one).
    int       label [N];
    payload_t group [N];                // by label
    int       root_of [N];              // by label

    function automatic void model_clear();
        for (int i = 0; i < N; i++) begin
            label[i]   = i;
            group[i]   = '0;
            root_of[i] = i;
        end
    endfunction

    // The root of an answer must be the group's root.
    task automatic check_root(int expected, int root, string what);
        if (root != expected)
            `DC_TEST_FAIL(root, $sformatf("N=%0d %s: root %0d, the group's root %0d", N, what,
                                          root, expected))
    endtask

    task automatic check(req_t q, rsp_t r);
        int       la;
        int       lb;
        payload_t exp;
        la = label[q.a];
        lb = label[q.b];
        case (q.op)
        DS_FIND, DS_SET: begin
            if (q.op == DS_SET)
                group[la] = q.payload;
            exp = group[la];
            if (r.payload !== exp || r.same !== 1'b0)
                `DC_TEST_FAIL(model, $sformatf(
                    "N=%0d op %0d a %0d: payload %h same %b, expected %h", N, q.op, q.a,
                    r.payload, r.same, exp))
            check_root(root_of[la], int'(r.root), "find/set");
        end
        DS_UNION:
            if (la == lb) begin
                if (r.same !== 1'b1 || r.payload !== group[la])
                    `DC_TEST_FAIL(model, $sformatf("N=%0d union %0d %0d of one group: same %b",
                                                   N, q.a, q.b, r.same))
                check_root(root_of[la], int'(r.root), "union of one group");
            end else begin
                exp = merged(group[la], group[lb]);
                if (r.same !== 1'b0 || r.payload !== exp)
                    `DC_TEST_FAIL(model, $sformatf(
                        "N=%0d union %0d %0d: payload %h same %b, expected %h", N, q.a, q.b,
                        r.payload, r.same, exp))
                if (int'(r.root) != root_of[la] && int'(r.root) != root_of[lb])
                    `DC_TEST_FAIL(root, $sformatf(
                        "N=%0d union %0d %0d: root %0d, not %0d or %0d", N, q.a, q.b, r.root,
                        root_of[la], root_of[lb]))
                for (int i = 0; i < N; i++)
                    if (label[i] == lb)
                        label[i] = la;
                group[la]   = exp;
                root_of[la] = int'(r.root);
            end
        DS_CLEAR: begin
            model_clear();
            if (r.root !== '0 || r.payload !== '0 || r.same !== 1'b0)
                `DC_TEST_FAIL(model, $sformatf("N=%0d clear: root %0d payload %h", N, r.root,
                                               r.payload))
        end
        endcase
    endtask

    initial begin
        int     n_checked;
        logic   seen_same;
        logic   seen_merge;             // a union of two groups of 2 or more
        logic   seen_clear;
        seed       = N;
        done       = 1'b0;
        seen_same  = 1'b0;
        seen_merge = 1'b0;
        seen_clear = 1'b0;
        rst_n      = 1'b0;
        u_source.gap_pct   = 30;
        u_sink.ready_pct   = 60;
        model_clear();
        for (int i = 0; i < N_OPS; i++) begin
            req_t q;
            int   kind;
            kind      = int'($unsigned($random(seed)) % 200);
            q.op      = kind == 0 || i == N_OPS / 2 ? DS_CLEAR :    // one clear at least
                        kind < 100 ? DS_UNION : kind < 160 ? DS_FIND : DS_SET;
            q.a       = IW'($unsigned($random(seed)) % N);
            q.b       = IW'($unsigned($random(seed)) % N);
            q.payload = payload_t'($random(seed));
            ops.push_back(req_v'(q));
            u_source.push(req_v'(q));
        end
        repeat (2) @(posedge clk);
        #1 rst_n = 1'b1;                                    // away from the edge
        n_checked = 0;
        while (n_checked < N_OPS) begin
            @(posedge clk);
            #1;
            while (u_sink.received.size() > 0) begin
                req_t q;
                rsp_t r;
                q = req_t'(ops.pop_front());
                r = rsp_t'(u_sink.received.pop_front());
                seen_same  |= q.op == DS_UNION && r.same;
                seen_clear |= q.op == DS_CLEAR;
                if (q.op == DS_UNION && label[q.a] != label[q.b]) begin
                    int na;
                    int nb;
                    na = 0;
                    nb = 0;
                    for (int i = 0; i < N; i++) begin
                        na += int'(label[i] == label[q.a]);
                        nb += int'(label[i] == label[q.b]);
                    end
                    seen_merge |= na >= 2 && nb >= 2;
                end
                check(q, r);
                n_checked++;
            end
        end
        if (!seen_same || (N >= 4 && !seen_merge) || !seen_clear)
            `DC_TEST_FAIL(cover, $sformatf("N=%0d: same %b merge %b clear %b", N, seen_same,
                                           seen_merge, seen_clear))
        done = 1'b1;
    end
endmodule

module TbDisjointSet;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    wire  done_2, done_5, done_16, done_64;

    initial clk = 1'b0;
    always #5 clk = !clk;

    TbDisjointSetCheck #(.N(2))  u_check_2 (.clk, .done(done_2));
    TbDisjointSetCheck #(.N(5))  u_check_5 (.clk, .done(done_5));
    TbDisjointSetCheck #(.N(16)) u_check_16(.clk, .done(done_16));
`ifdef VERILATOR
    // The struct version of 64 items takes seconds to elaborate on event-driven Icarus.
    TbDisjointSetCheck #(.N(64)) u_check_64(.clk, .done(done_64));
`else
    assign done_64 = 1'b1;
`endif

    initial begin
        wait (done_2 && done_5 && done_16 && done_64);
        $display("PASS");
        $finish;
    end
endmodule
