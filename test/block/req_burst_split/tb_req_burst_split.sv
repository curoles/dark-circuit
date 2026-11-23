/* Test of ReqBurstSplit, behave or struct version.
 *
 * The testbench is the requester and the target. The requester offers random requests (a
 * burst read of 1 to 1 << LEN_WIDTH beats, a single read, a write that wants an answer or
 * not; any address, size 1, 2 or 4 bytes, random fields) and holds one that is not taken.
 * When one is taken, it must be in a clock where the target takes its beat 0 and no beat
 * of the request before is left; its beats are remembered, {we, rsp, address of beat k =
 * address + (k << size), size, fields}, and, as a requester's ReqDemux or ReqMux would,
 * the answers it waits for are counted (len + 1 with req_rsp). The target is ready in 70 %
 * of the clocks; every beat it takes must be the oldest remembered one, and it answers the
 * beats with req_rsp in order, 1 to 3 clocks after it took each. Every answer must find
 * the requester waiting for one (a burst taken only with its last beat would get its first
 * answers before it was counted). At the end no beat and no answer is left. 3000 clocks on
 * Verilator, 400 on Icarus; LEN_WIDTH 1 (bursts of 2) and 4 (up to 16). Every case must
 * happen (checks named cover): a burst of the most beats, a single read, a write, a target
 * not ready in a burst, a request taken in the clock after a burst's last beat. Checks named
 * model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbReqBurstSplitCheck #(
    parameter LEN_WIDTH = 4
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
    localparam AW      = 16;
    localparam FW      = 8;
    localparam MAX_LEN = (1 << LEN_WIDTH) - 1;
    localparam BW      = 2 + AW + 3 + FW;       // a beat: we, rsp, addr, size, fields

    logic                 req_valid;
    wire                  req_ready;
    logic                 req_we;
    logic                 req_rsp;
    logic [LEN_WIDTH-1:0] req_len;
    logic [AW-1:0]        req_addr;
    logic [2:0]           req_size;
    logic [FW-1:0]        req_fields;
    wire                  tgt_req_valid;
    logic                 tgt_req_ready;
    wire                  tgt_req_we;
    wire                  tgt_req_rsp;
    wire  [AW-1:0]        tgt_req_addr;
    wire  [2:0]           tgt_req_size;
    wire  [FW-1:0]        tgt_req_fields;

    logic [BW-1:0]        beats [$];            // the beats remembered, not taken
    int                   ans_due [$];          // the target's answers due, in order
    int                   owed;                 // answers the requester waits for
    int                   cycle;
    integer               seed;
    bit                   seen_max, seen_single, seen_write, seen_stall, seen_b2b;

    ReqBurstSplit #(.ADDR_WIDTH(AW), .FIELDS_WIDTH(FW), .LEN_WIDTH(LEN_WIDTH)) u_split(
        .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_rsp, .req_len, .req_addr,
        .req_size, .req_fields, .tgt_req_valid, .tgt_req_ready, .tgt_req_we, .tgt_req_rsp,
        .tgt_req_addr, .tgt_req_size, .tgt_req_fields);

    initial begin
        bit last_taken;             // a burst's last beat was taken in the clock before
        bit busy_beat;              // the beat out is not a request's beat 0
        bit taken;                  // the offer was taken at the edge before
        done = 1'b0;
        seed = LEN_WIDTH;
        {seen_max, seen_single, seen_write, seen_stall, seen_b2b} = '0;
        req_valid     = 1'b0;
        req_we        = 1'b0;
        req_rsp       = 1'b0;
        req_len       = '0;
        req_addr      = '0;
        req_size      = '0;
        req_fields    = '0;
        tgt_req_ready = 1'b0;
        owed          = 0;
        cycle         = 0;
        last_taken    = 1'b0;
        taken         = 1'b0;
        @(posedge rst_n);
        forever begin
            bit answer, take, tgt_take;
            @(negedge clk);
            cycle++;
            // The requester: a new offer once the last one was taken (none at the end).
            if (taken)
                req_valid = 1'b0;
            if (!req_valid && cycle < N_CYCLES && $unsigned($random(seed)) % 4 != 0) begin
                int kind;
                kind       = $unsigned($random(seed)) % 10;
                req_valid  = 1'b1;
                req_we     = kind >= 8;                     // a write: 2 in 10
                req_rsp    = kind < 8 || kind == 9;         // ... answered or not
                req_len    = (kind < 5) ? LEN_WIDTH'($unsigned($random(seed)) % (MAX_LEN + 1))
                                        : '0;               // a burst read: 5 in 10
                if (kind < 5 && $unsigned($random(seed)) % 4 == 0)
                    req_len = LEN_WIDTH'(MAX_LEN);
                req_addr   = AW'($random(seed));
                req_size   = 3'($unsigned($random(seed)) % 3);
                req_fields = FW'($random(seed));
            end
            // The target.
            tgt_req_ready = $unsigned($random(seed)) % 10 < 7;
            answer        = ans_due.size() > 0 && ans_due[0] <= cycle;
            #1;
            // The answer of this clock: the requester must be waiting for it.
            if (answer) begin
                if (owed == 0)
                    `DC_TEST_FAIL(model, $sformatf(
                        "ReqBurstSplit %0d: an answer before its request was taken", LEN_WIDTH))
                owed--;
                void'(ans_due.pop_front());
            end
            take     = req_valid && req_ready;
            tgt_take = tgt_req_valid && tgt_req_ready;
            busy_beat = beats.size() > 0;
            // A take: with its beat 0, no beat of the request before left.
            if (take) begin
                if (busy_beat || !tgt_take)
                    `DC_TEST_FAIL(model, $sformatf(
                        "ReqBurstSplit %0d: taken with %0d beats left, target take %b", LEN_WIDTH,
                        beats.size(), tgt_take))
                for (int k = 0; k <= int'(req_len); k++)
                    beats.push_back({req_we, req_rsp, AW'(req_addr + (AW'(k) << req_size)),
                                     req_size, req_fields});
                if (req_rsp)
                    owed += int'(req_len) + 1;
                if (int'(req_len) == MAX_LEN)        seen_max    = 1'b1;
                if (req_len == '0 && !req_we)        seen_single = 1'b1;
                if (req_we)                          seen_write  = 1'b1;
                if (last_taken && req_len != '0)     seen_b2b    = 1'b1;
            end
            if (busy_beat && tgt_req_valid && !tgt_req_ready)
                seen_stall = 1'b1;
            // A beat taken: the oldest remembered; answered later in order.
            last_taken = 1'b0;
            if (tgt_take) begin
                logic [BW-1:0] b;
                if (beats.size() == 0)
                    `DC_TEST_FAIL(model, $sformatf("ReqBurstSplit %0d: a beat of nothing",
                                                   LEN_WIDTH))
                b = beats.pop_front();
                if ({tgt_req_we, tgt_req_rsp, tgt_req_addr, tgt_req_size, tgt_req_fields} !== b)
                    `DC_TEST_FAIL(model, $sformatf(
                        {"ReqBurstSplit %0d: beat we %b rsp %b addr %h size %0d fields %h,",
                         " expected %h"},
                        LEN_WIDTH, tgt_req_we, tgt_req_rsp, tgt_req_addr, tgt_req_size,
                        tgt_req_fields, b))
                if (tgt_req_rsp)
                    ans_due.push_back(cycle + 1 + $unsigned($random(seed)) % 3);
                last_taken = busy_beat && beats.size() == 0;
            end else if (tgt_req_valid && beats.size() == 0 && !req_valid)
                `DC_TEST_FAIL(model, $sformatf("ReqBurstSplit %0d: a beat offered of nothing",
                                               LEN_WIDTH))
            taken = take;
            if (cycle >= N_CYCLES && (!req_valid || take) && beats.size() == 0 &&
                ans_due.size() == 0)
                break;
            if (cycle > N_CYCLES + 200)
                `DC_TEST_FAIL(model, $sformatf("ReqBurstSplit %0d: no end", LEN_WIDTH))
        end
        if (owed != 0)
            `DC_TEST_FAIL(model, $sformatf("ReqBurstSplit %0d: %0d answers owed at the end",
                                           LEN_WIDTH, owed))
        if (!seen_max || !seen_single || !seen_write || !seen_stall || !seen_b2b)
            `DC_TEST_FAIL(cover, $sformatf(
                "ReqBurstSplit %0d: max %b single %b write %b stall %b back to back %b",
                LEN_WIDTH, seen_max, seen_single, seen_write, seen_stall, seen_b2b))
        done = 1'b1;
    end
endmodule

module TbReqBurstSplit;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_1, done_4;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbReqBurstSplitCheck #(.LEN_WIDTH(1)) u_check_1(.clk, .rst_n, .done(done_1));
    TbReqBurstSplitCheck #(.LEN_WIDTH(4)) u_check_4(.clk, .rst_n, .done(done_4));

    initial begin
        wait (done_1 && done_4);
        $display("PASS");
        $finish;
    end
endmodule
