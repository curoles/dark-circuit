/* Test of ReqDemux, behave or struct version.
 *
 * The testbench is the initiator and the targets. The initiator offers random requests
 * (nothing, a read or a write; mostly the target before, a random one in a quarter) and
 * holds one that is not taken. Each target is ready in 70 % of the clocks and answers its
 * reads in order, each 1 to 2 << PENDING_WIDTH clocks after it took it (so reads pile up to
 * the full count), with a token (a number per read, unique). A model of the demux (reads pending,
 * their target) gives in every clock tgt_req_valid (only the selected target, only when the
 * request does not wait: another target while reads wait, or a read while 1 << PENDING_WIDTH
 * wait), req_ready, and every answer: the token of the oldest read not answered, in the
 * order the reads were taken. 3000 clocks on Verilator, 400 on Icarus; 2 targets with up to
 * 2 reads waiting, 3 targets with up to 4. Every case must happen (checks named cover): a
 * request to another target that waits, a read that waits for a full count, reads to the
 * same target while one waits, a write taken, a request taken by every target. Checks named
 * model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbReqDemuxCheck #(
    parameter N_TARGETS     = 2,
    parameter PENDING_WIDTH = 1
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
`ifdef VERILATOR
    localparam N_CYCLES = 3000;
`else
    localparam N_CYCLES = 400;
`endif
    localparam MAX = 1 << PENDING_WIDTH;
    localparam RW  = 16;    // bits of an answer: a token
    localparam QD  = 16;    // reads a target keeps, more than MAX
    localparam ED  = 64;    // answers the initiator waits for, more than MAX

    logic                          req_valid;
    wire                           req_ready;
    logic                          req_we;
    logic [N_TARGETS-1:0]          req_sel;
    wire                           rsp_valid;
    wire  [RW-1:0]                 rsp_data;
    wire  [N_TARGETS-1:0]          tgt_req_valid;
    logic [N_TARGETS-1:0]          tgt_req_ready;
    logic [N_TARGETS-1:0]          tgt_rsp_valid;
    logic [N_TARGETS-1:0][RW-1:0]  tgt_rsp_data;
    integer                        seed;

    ReqDemux #(.N_TARGETS(N_TARGETS), .RSP_WIDTH(RW), .PENDING_WIDTH(PENDING_WIDTH)) u_req_demux(
        .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_sel, .rsp_valid, .rsp_data,
        .tgt_req_valid, .tgt_req_ready, .tgt_rsp_valid, .tgt_rsp_data);

    // The targets: reads taken and not answered, a circular queue each (flat: target t's
    // entries at t * QD).
    int t_tok  [N_TARGETS*QD];
    int t_due  [N_TARGETS*QD];      // the cycle its answer may come
    int t_head [N_TARGETS];
    int t_tail [N_TARGETS];
    // The model at the initiator: answers expected, in order; reads pending and their target.
    int e_tok [ED];
    int e_head, e_tail;
    int pend;
    logic [N_TARGETS-1:0] owner;
    int tok_next, cyc;
    logic seen_other_wait, seen_full_wait, seen_same, seen_write;
    logic [N_TARGETS-1:0] seen_taken;

    function automatic logic blocked();
        return (pend > 0 && (req_sel & ~owner) != '0) || (pend == MAX && !req_we);
    endfunction

    function automatic int target_of(input logic [N_TARGETS-1:0] s);
        for (int t = 0; t < N_TARGETS; t++)
            if (s[t])
                return t;
        return 0;
    endfunction

    // Mostly the target of the request before (reads pile up), now and then another.
    task automatic new_request();
        req_valid = ($random(seed) % 4) != 0;
        req_we    = ($random(seed) % 3) == 0;
        if (req_sel == '0 || ({$random(seed)} % 4) == 0)
            req_sel = N_TARGETS'(1) << ({$random(seed)} % N_TARGETS);
    endtask

    initial begin
        logic            exp_rsp, taken;
        int              t;
        logic [RW-1:0]   d;
        done = 1'b0;
        seed = N_TARGETS * 16 + PENDING_WIDTH;
        {seen_other_wait, seen_full_wait, seen_same, seen_write} = '0;
        seen_taken = '0;
        for (int i = 0; i < N_TARGETS; i++) begin
            t_head[i] = 0;
            t_tail[i] = 0;
        end
        e_head = 0;
        e_tail = 0;
        pend = 0;
        owner = '0;
        tok_next = 1;
        cyc = 0;
        tgt_rsp_valid = '0;
        tgt_rsp_data  = '0;
        tgt_req_ready = '0;
        req_sel       = '0;
        new_request();
        @(posedge rst_n);
        @(posedge clk);
        #1;
        repeat (N_CYCLES) begin
            @(negedge clk);
            // The middle of the clock: the outputs of this clock.
            if (tgt_req_valid !== ((req_valid && !blocked()) ? req_sel : '0) ||
                req_ready !== (!blocked() && (tgt_req_ready & req_sel) != '0))
                `DC_TEST_FAIL(model, $sformatf({
                    "ReqDemux %0d targets: tgt_req_valid %b ready %b, valid %b sel %b we %b, ",
                    "pending %0d owner %b"}, N_TARGETS, tgt_req_valid, req_ready, req_valid,
                    req_sel, req_we, pend, owner))
            exp_rsp = tgt_rsp_valid != '0;
            if (rsp_valid !== exp_rsp || (exp_rsp && rsp_data !== RW'(e_tok[e_head % ED])))
                `DC_TEST_FAIL(model, $sformatf("ReqDemux %0d targets: rsp %b %h, expected %b %h",
                    N_TARGETS, rsp_valid, rsp_data, exp_rsp, RW'(e_tok[e_head % ED])))
            taken = req_valid && req_ready;
            t     = target_of(req_sel);
            if (req_valid && pend > 0 && (req_sel & ~owner) != '0)
                seen_other_wait = 1'b1;
            if (req_valid && pend == MAX && !req_we && (req_sel & ~owner) == '0)
                seen_full_wait = 1'b1;
            if (taken && !req_we && pend > 0)
                seen_same = 1'b1;
            if (taken && req_we)
                seen_write = 1'b1;
            if (taken)
                seen_taken[t] = 1'b1;
            // The model at the edge.
            if (exp_rsp) begin
                e_head = e_head + 1;
                pend   = pend - 1;
            end
            if (taken && !req_we) begin
                e_tok[e_tail % ED] = tok_next;
                e_tail = e_tail + 1;
                t_tok[t * QD + t_tail[t] % QD] = tok_next;
                t_due[t * QD + t_tail[t] % QD] = cyc + 1 + {$random(seed)} % (2 * MAX);
                t_tail[t] = t_tail[t] + 1;
                tok_next = tok_next + 1;
                pend  = pend + 1;
                owner = req_sel;
            end
            @(posedge clk);
            #1;
            cyc = cyc + 1;
            // The targets: the oldest read of each answers when its time has come.
            for (int i = 0; i < N_TARGETS; i++) begin
                tgt_rsp_valid[i] = 1'b0;
                if (t_head[i] != t_tail[i] && t_due[i * QD + t_head[i] % QD] <= cyc) begin
                    d = RW'(t_tok[i * QD + t_head[i] % QD]);
                    tgt_rsp_valid[i] = 1'b1;
                    tgt_rsp_data[i]  = d;
                    t_head[i] = t_head[i] + 1;
                end
            end
            // The next offer: a new one after a request was taken or nothing offered.
            if (taken || !req_valid)
                new_request();
            for (int i = 0; i < N_TARGETS; i++)
                tgt_req_ready[i] = ({$random(seed)} % 10) < 7;
        end
        if (!seen_other_wait || !seen_full_wait || !seen_same || !seen_write ||
            seen_taken !== '1)
            `DC_TEST_FAIL(cover, $sformatf({
                "ReqDemux %0d targets: other wait %b full wait %b same %b write %b taken %b"},
                N_TARGETS, seen_other_wait, seen_full_wait, seen_same, seen_write, seen_taken))
        done = 1'b1;
    end
endmodule

module TbReqDemux;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_2, done_3;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbReqDemuxCheck #(.N_TARGETS(2), .PENDING_WIDTH(1)) u_check_2(.clk, .rst_n, .done(done_2));
    TbReqDemuxCheck #(.N_TARGETS(3), .PENDING_WIDTH(2)) u_check_3(.clk, .rst_n, .done(done_3));

    initial begin
        wait (done_2 && done_3);
        $display("PASS");
        $finish;
    end
endmodule
