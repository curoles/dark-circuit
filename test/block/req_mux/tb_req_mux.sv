/* Test of ReqMux, behave or struct version.
 *
 * The testbench is every requester and the target. Each requester offers random reads,
 * posted writes (req_rsp=0) and writes that want an answer (req_rsp=1), each with a token in
 * its fields (its number and a sequence number), and holds an offer until it is taken. The
 * target is ready in 60 % of the clocks and answers each request with req_rsp with its
 * token, 1 to 6 clocks after taking it (one in eight 10 to 19: answers pile up), in order.
 * Model: per requester the tokens of its requests not answered yet and of its posted writes
 * not at the target yet, in its order. Every clock: an offer to the target that waits stays
 * the same; a posted write the target takes is the next one of its requester; an answer goes
 * to exactly one requester, the one whose oldest request it answers, with that token; a
 * requester's ready only with its valid. At the end every request is answered and every
 * posted write arrived. Configurations: 3 requesters with 2 answers waiting at most, 2 with
 * 4, 1 with 2; 400 requests a requester on Verilator, 80 on Icarus. Every case must happen
 * (checks named cover): two requesters offering at once, an offer the target does not take
 * at once, a request waiting for a full FIFO, every kind of request from every requester.
 * Checks named model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbReqMuxCheck #(
    parameter N_REQ         = 3,
    parameter PENDING_WIDTH = 1
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
`ifdef VERILATOR
    localparam N_OPS = 400;
`else
    localparam N_OPS = 80;
`endif
    localparam N  = N_REQ;
    localparam QD = 1024;               // a requester's queues: entries

    logic [N-1:0]         req_valid;
    wire  [N-1:0]         req_ready;
    logic [N-1:0]         req_we;
    logic [N-1:0]         req_rsp;
    logic [N-1:0][31:0]   req_fields;
    wire  [N-1:0]         rsp_valid;
    wire  [31:0]          rsp_data;
    wire                  tgt_req_valid;
    logic                 tgt_req_ready;
    wire                  tgt_req_we;
    wire                  tgt_req_rsp;
    wire  [31:0]          tgt_req_fields;
    logic                 tgt_rsp_valid;
    logic [31:0]          tgt_rsp_data;

    logic [31:0]          rd_q [N][QD];     // tokens of requests not answered, in order
    int                   rd_head [N], rd_tail [N];
    logic [31:0]          wr_q [N][QD];     // tokens of posted writes not at the target
    int                   wr_head [N], wr_tail [N];
    logic [31:0]          ans [$];          // the target's answers due, in order
    int                   due [$];
    int                   cycle;
    integer               seed;
    bit                   seen_two, seen_wait, seen_full;
    logic [N-1:0]         seen_read, seen_write, seen_ack;

    ReqMux #(.N_REQ(N), .REQ_WIDTH(32), .RSP_WIDTH(32), .PENDING_WIDTH(PENDING_WIDTH))
        u_req_mux(
            .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_rsp, .req_fields, .rsp_valid,
            .rsp_data, .tgt_req_valid, .tgt_req_ready, .tgt_req_we, .tgt_req_rsp,
            .tgt_req_fields, .tgt_rsp_valid, .tgt_rsp_data);

    initial begin
        int   sent [N];
        int   r;
        logic [N-1:0] taken;                // requests taken at the coming edge
        logic prev_wait;
        logic prev_we;
        logic prev_rsp;
        logic [31:0] prev_fields;
        done = 1'b0;
        seed = 31 * N + PENDING_WIDTH;
        {seen_two, seen_wait, seen_full} = '0;
        {seen_read, seen_write, seen_ack} = '0;
        req_valid     = '0;
        req_we        = '0;
        req_rsp       = '0;
        req_fields    = '0;
        tgt_req_ready = 1'b0;
        tgt_rsp_valid = 1'b0;
        tgt_rsp_data  = '0;
        cycle         = 0;
        prev_wait     = 1'b0;
        prev_we       = 1'b0;
        prev_rsp      = 1'b0;
        prev_fields   = '0;
        taken         = '0;
        for (int i = 0; i < N; i++) begin
            sent[i]    = 0;
            rd_head[i] = 0;
            rd_tail[i] = 0;
            wr_head[i] = 0;
            wr_tail[i] = 0;
        end
        @(posedge rst_n);
        forever begin
            // The inputs of this clock.
            @(negedge clk);
            cycle++;
            req_valid = req_valid & ~taken;         // taken at the rising edge before
            for (int i = 0; i < N; i++)
                if (!req_valid[i] && sent[i] < N_OPS && $unsigned($random(seed)) % 2 == 0) begin
                    req_valid[i]  = 1'b1;
                    case ($unsigned($random(seed)) % 3)
                        0:       {req_we[i], req_rsp[i]} = 2'b01;    // a read
                        1:       {req_we[i], req_rsp[i]} = 2'b10;    // a posted write
                        default: {req_we[i], req_rsp[i]} = 2'b11;    // answered write
                    endcase
                    req_fields[i] = {8'(i), 16'(sent[i]), 8'($random(seed))};
                    sent[i]++;
                end
            tgt_req_ready = $unsigned($random(seed)) % 10 < 6;
            tgt_rsp_valid = ans.size() > 0 && due[0] <= cycle;
            tgt_rsp_data  = tgt_rsp_valid ? ans[0] : '0;
            #1;
            // Checks of this clock.
            if (prev_wait && (!tgt_req_valid || tgt_req_we !== prev_we ||
                              tgt_req_rsp !== prev_rsp || tgt_req_fields !== prev_fields))
                `DC_TEST_FAIL(model, $sformatf("ReqMux %0d: a waiting offer changed", N))
            if ((req_ready & ~req_valid) != '0)
                `DC_TEST_FAIL(model, $sformatf("ReqMux %0d: ready %b without valid %b", N,
                                               req_ready, req_valid))
            if ($countones(req_valid) > 1)                   seen_two  = 1'b1;
            if (u_req_mux.grant != '0 && !tgt_req_valid)     seen_full = 1'b1;
            prev_wait   = tgt_req_valid && !tgt_req_ready;
            if (prev_wait)                                   seen_wait = 1'b1;
            prev_we     = tgt_req_we;
            prev_rsp    = tgt_req_rsp;
            prev_fields = tgt_req_fields;
            if (tgt_rsp_valid) begin
                if (!$onehot(rsp_valid))
                    `DC_TEST_FAIL(model, $sformatf("ReqMux %0d: answer to %b", N, rsp_valid))
                r = $clog2(rsp_valid);
                if (rd_head[r] == rd_tail[r] || rsp_data !== rd_q[r][rd_head[r] % QD])
                    `DC_TEST_FAIL(model, $sformatf("ReqMux %0d: requester %0d got %h", N, r,
                                                   rsp_data))
                rd_head[r]++;
                void'(ans.pop_front());
                void'(due.pop_front());
            end else if (rsp_valid != '0)
                `DC_TEST_FAIL(model, $sformatf("ReqMux %0d: answer %b without one", N,
                                               rsp_valid))
            // The edge: the requests taken.
            taken = req_valid & req_ready;
            for (int i = 0; i < N; i++)
                if (taken[i]) begin
                    if (!req_rsp[i]) begin
                        wr_q[i][wr_tail[i] % QD] = req_fields[i];
                        wr_tail[i]++;
                        seen_write[i] = 1'b1;
                    end else begin
                        rd_q[i][rd_tail[i] % QD] = req_fields[i];
                        rd_tail[i]++;
                        if (req_we[i]) seen_ack[i]  = 1'b1;
                        else           seen_read[i] = 1'b1;
                    end
                end
            if (tgt_req_valid && tgt_req_ready) begin
                r = int'(tgt_req_fields[31:24]);
                if (!tgt_req_rsp) begin
                    if (!tgt_req_we || wr_head[r] == wr_tail[r] ||
                        tgt_req_fields !== wr_q[r][wr_head[r] % QD])
                        `DC_TEST_FAIL(model, $sformatf("ReqMux %0d: write %h out of order", N,
                                                       tgt_req_fields))
                    wr_head[r]++;
                end else begin
                    ans.push_back(tgt_req_fields);
                    due.push_back(cycle + 1 + (($unsigned($random(seed)) % 8 == 0)
                                               ? 10 + $unsigned($random(seed)) % 10
                                               : $unsigned($random(seed)) % 6));
                end
            end
            // The end: everything sent, answered and arrived.
            begin
                bit all;
                all = ans.size() == 0 && (req_valid & ~taken) == '0;
                for (int i = 0; i < N; i++)
                    if (sent[i] < N_OPS || rd_head[i] != rd_tail[i] || wr_head[i] != wr_tail[i])
                        all = 1'b0;
                if (all)
                    break;
            end
            if (cycle > 50 * N * N_OPS)
                `DC_TEST_FAIL(model, $sformatf("ReqMux %0d: no end", N))
        end
        @(negedge clk);
        req_valid     = '0;                     // idle from now on
        tgt_req_ready = 1'b0;
        tgt_rsp_valid = 1'b0;
        if ((N > 1 && !seen_two) || !seen_wait || !seen_full || seen_read != '1 ||
            seen_write != '1 || seen_ack != '1)
            `DC_TEST_FAIL(cover, $sformatf(
                "ReqMux %0d: two %b wait %b full %b read %b write %b answered write %b", N,
                seen_two, seen_wait, seen_full, seen_read, seen_write, seen_ack))
        done = 1'b1;
    end
endmodule

module TbReqMux;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_3, done_2, done_1;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbReqMuxCheck #(.N_REQ(3), .PENDING_WIDTH(1)) u_check_3(.clk, .rst_n, .done(done_3));
    TbReqMuxCheck #(.N_REQ(2), .PENDING_WIDTH(2)) u_check_2(.clk, .rst_n, .done(done_2));
    TbReqMuxCheck #(.N_REQ(1), .PENDING_WIDTH(1)) u_check_1(.clk, .rst_n, .done(done_1));

    initial begin
        wait (done_3 && done_2 && done_1);
        $display("PASS");
        $finish;
    end
endmodule
