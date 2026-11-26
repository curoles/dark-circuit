/* Test of ReqDataWidthDown, behave or struct version.
 *
 * The testbench is the requester (a line wide) and the target (a word wide). The requester
 * offers random requests and holds one that is not taken: a line read (answered), a line
 * write (posted: strobes on some bytes of one random word, or none, as a CBO), a read of a
 * word or less (1, 2 or 4 bytes, aligned), a write of a word or less (answered or not; its
 * strobes in the word its address names); random data and fields. A request must be taken
 * in the clock the target takes its narrow request, which must be the expected one: a line
 * read a burst of LINE_WORDS words at the line, a line write the strobed word (word 0 with
 * none) at its address with its strobes, a word or less itself with the word its address
 * names. The target is ready in 70 % of the clocks and answers every word of a request with
 * req_rsp in order, 1 to 3 clocks apart, word a's answer f(a) (a fixed function of the
 * address). Every wide answer must be the expected one, in order: a line read's line of the
 * f of its words, a single word's f in every word. At the end nothing is owed. 3000 clocks on
 * Verilator, 400 on Icarus; LINE_WORDS 2 (PENDING_WIDTH 1), 4 (2) and 1 (the wires). Every
 * case must happen (checks named cover): each kind of request, a line write with no strobes,
 * an answered request held back by a full queue (LINE_WORDS above 1), a request taken in a
 * clock with an answer. Checks named model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbReqDataWidthDownCheck #(
    parameter LINE_WORDS    = 2,
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
    localparam AW        = 16;
    localparam WW        = 32;
    localparam FW        = 8;
    localparam LW        = 3;                   // narrow req_len: bursts of up to 8
    localparam WB        = WW / 8;              // bytes of a word
    localparam LWIDTH    = WW * LINE_WORDS;
    localparam LB        = LWIDTH / 8;          // bytes of a line
    localparam WORD_SIZE = $clog2(WB);
    localparam LINE_SIZE = $clog2(LB);
    // A narrow request: we, rsp, len, addr, size, wdata, wstrb, fields.
    localparam NW        = 2 + LW + AW + 3 + WW + WB + FW;

    logic              req_valid;
    wire               req_ready;
    logic              req_we;
    logic              req_rsp;
    logic [AW-1:0]     req_addr;
    logic [2:0]        req_size;
    logic [LWIDTH-1:0] req_wdata;
    logic [LB-1:0]     req_wstrb;
    logic [FW-1:0]     req_fields;
    wire               rsp_valid;
    wire  [LWIDTH-1:0] rsp_data;
    wire               tgt_req_valid;
    logic              tgt_req_ready;
    wire               tgt_req_we;
    wire               tgt_req_rsp;
    wire  [LW-1:0]     tgt_req_len;
    wire  [AW-1:0]     tgt_req_addr;
    wire  [2:0]        tgt_req_size;
    wire  [WW-1:0]     tgt_req_wdata;
    wire  [WB-1:0]     tgt_req_wstrb;
    wire  [FW-1:0]     tgt_req_fields;
    logic              tgt_rsp_valid;
    logic [WW-1:0]     tgt_rsp_data;

    logic [NW-1:0]     expect_req;              // the narrow request of the offer
    logic [LWIDTH-1:0] rsp_due [$];             // the wide answers owed, in order
    int                ans_due [$];             // the target's answers: due cycles
    logic [WW-1:0]     ans_data [$];            // ... and words
    int                last_due;                // the latest due cycle given
    int                cycle;
    integer            seed;
    bit                seen_line_rd, seen_line_wr, seen_cbo, seen_rd, seen_wr, seen_blocked;
    bit                seen_overlap;

    ReqDataWidthDown #(.ADDR_WIDTH(AW), .WORD_WIDTH(WW), .LINE_WORDS(LINE_WORDS),
                       .FIELDS_WIDTH(FW), .LEN_WIDTH(LW), .PENDING_WIDTH(PENDING_WIDTH))
        u_down(.clk, .rst_n, .req_valid, .req_ready, .req_we, .req_rsp, .req_addr, .req_size,
               .req_wdata, .req_wstrb, .req_fields, .rsp_valid, .rsp_data, .tgt_req_valid,
               .tgt_req_ready, .tgt_req_we, .tgt_req_rsp, .tgt_req_len, .tgt_req_addr,
               .tgt_req_size, .tgt_req_wdata, .tgt_req_wstrb, .tgt_req_fields, .tgt_rsp_valid,
               .tgt_rsp_data);

    // The target's answer for the word at byte address a.
    function automatic logic [WW-1:0] f(input logic [AW-1:0] a);
        return WW'(a) * 32'h9E3779B1 ^ 32'h5A5A1234;
    endfunction

    // A new offer and its expected narrow request and answer.
    task automatic offer;
        int            kind;
        int            w;               // the word of the line it goes as
        logic [AW-1:0] line_addr;
        logic [AW-1:0] a;               // the narrow request's address
        logic [2:0]    size;
        logic [LW-1:0] len;
        kind       = $unsigned($random(seed)) % 8;
        req_valid  = 1'b1;
        req_fields = FW'($random(seed));
        for (int i = 0; i < LINE_WORDS; i++)
            req_wdata[i * WW +: WW] = WW'($random(seed));
        req_wstrb  = '0;
        line_addr  = AW'($random(seed)) & ~AW'(LB - 1);
        if (kind < 2) begin                         // a line read
            req_we   = 1'b0;
            req_rsp  = 1'b1;
            req_addr = line_addr;
            req_size = 3'(LINE_SIZE);
            w        = 0;
            a        = line_addr;
            size     = 3'(WORD_SIZE);
            len      = LW'(LINE_WORDS - 1);
        end else if (kind < 4) begin                // a line write: one word's bytes or none
            req_we   = 1'b1;
            req_rsp  = 1'b0;
            req_addr = line_addr;
            req_size = 3'(LINE_SIZE);
            w        = $unsigned($random(seed)) % LINE_WORDS;
            if ($unsigned($random(seed)) % 4 == 0)
                w = 0;                              // no strobes: word 0
            else
                req_wstrb[w * WB +: WB] = WB'($unsigned($random(seed)) % ((1 << WB) - 1) + 1);
            a        = line_addr + AW'(w * WB);
            size     = 3'(WORD_SIZE);
            len      = '0;
        end else begin                              // a word or less
            req_we   = kind >= 6;
            req_rsp  = !req_we || kind == 7;
            req_size = 3'($unsigned($random(seed)) % (WORD_SIZE + 1));
            req_addr = AW'($random(seed)) & ~AW'((1 << req_size) - 1);
            w        = (int'(req_addr) % LB) / WB;
            if (req_we)
                req_wstrb[w * WB +: WB] = WB'($random(seed));
            a        = req_addr;
            size     = req_size;
            len      = '0;
        end
        expect_req = {req_we, req_rsp, len, a, size, req_wdata[w * WB * 8 +: WW],
                      req_wstrb[w * WB +: WB], req_fields};
    endtask

    // The wide answer the offer gets.
    function automatic logic [LWIDTH-1:0] answer_of();
        logic [LWIDTH-1:0] l;
        for (int i = 0; i < LINE_WORDS; i++)
            if (req_size == 3'(LINE_SIZE) && !req_we)
                l[i * WW +: WW] = f(req_addr + AW'(i * WB));
            else
                l[i * WW +: WW] = f(req_addr & ~AW'(WB - 1));
        return l;
    endfunction

    initial begin
        bit taken;                  // the offer was taken at the edge before
        done = 1'b0;
        seed = LINE_WORDS * 13 + PENDING_WIDTH;
        {seen_line_rd, seen_line_wr, seen_cbo, seen_rd, seen_wr, seen_blocked} = '0;
        seen_overlap  = 1'b0;
        req_valid     = 1'b0;
        req_we        = 1'b0;
        req_rsp       = 1'b0;
        req_addr      = '0;
        req_size      = '0;
        req_wdata     = '0;
        req_wstrb     = '0;
        req_fields    = '0;
        tgt_req_ready = 1'b0;
        tgt_rsp_valid = 1'b0;
        tgt_rsp_data  = '0;
        expect_req    = '0;
        cycle         = 0;
        last_due      = 0;
        taken         = 1'b0;
        @(posedge rst_n);
        forever begin
            bit take, tgt_take, answer;
            @(negedge clk);
            cycle++;
            // The requester: a new offer once the last one was taken (none at the end).
            if (taken)
                req_valid = 1'b0;
            if (!req_valid && cycle < N_CYCLES && $unsigned($random(seed)) % 4 != 0)
                offer();
            // The target: ready or not; the answer due in this clock.
            tgt_req_ready = $unsigned($random(seed)) % 10 < 7;
            answer        = ans_due.size() > 0 && ans_due[0] <= cycle;
            tgt_rsp_valid = answer;
            tgt_rsp_data  = answer ? ans_data[0] : '0;
            #1;
            take     = req_valid && req_ready;
            tgt_take = tgt_req_valid && tgt_req_ready;
            if (take != tgt_take)
                `DC_TEST_FAIL(model, $sformatf(
                    "ReqDataWidthDown %0d: taken %b, the target took %b", LINE_WORDS, take,
                    tgt_take))
            if (req_valid && req_rsp && !req_ready && tgt_req_ready)
                seen_blocked = 1'b1;
            // The answer of this clock; a wide answer must be the oldest owed.
            if (answer) begin
                void'(ans_due.pop_front());
                void'(ans_data.pop_front());
            end
            if (rsp_valid) begin
                if (rsp_due.size() == 0)
                    `DC_TEST_FAIL(model, $sformatf("ReqDataWidthDown %0d: an answer of nothing",
                                                   LINE_WORDS))
                if (rsp_data !== rsp_due[0])
                    `DC_TEST_FAIL(model, $sformatf(
                        "ReqDataWidthDown %0d: answer %h, expected %h", LINE_WORDS, rsp_data,
                        rsp_due[0]))
                void'(rsp_due.pop_front());
            end
            // A take: the expected narrow request; its answers scheduled, the wide one owed.
            if (take) begin
                logic [NW-1:0] got;
                got = {tgt_req_we, tgt_req_rsp, tgt_req_len, tgt_req_addr, tgt_req_size,
                       tgt_req_wdata, tgt_req_wstrb, tgt_req_fields};
                if (got !== expect_req)
                    `DC_TEST_FAIL(model, $sformatf(
                        "ReqDataWidthDown %0d: narrow request %h, expected %h", LINE_WORDS, got,
                        expect_req))
                if (req_rsp) begin
                    rsp_due.push_back(answer_of());
                    for (int k = 0; k <= int'(tgt_req_len); k++) begin
                        last_due = ((last_due > cycle) ? last_due : cycle) + 1 +
                                   $unsigned($random(seed)) % 3;
                        ans_due.push_back(last_due);
                        ans_data.push_back(f((tgt_req_addr & ~AW'(WB - 1)) + AW'(k * WB)));
                    end
                end
                if (req_size == 3'(LINE_SIZE) && !req_we)    seen_line_rd = 1'b1;
                if (req_size == 3'(LINE_SIZE) && req_we && req_wstrb != '0) seen_line_wr = 1'b1;
                if (req_size == 3'(LINE_SIZE) && req_we && req_wstrb == '0) seen_cbo = 1'b1;
                if (req_size != 3'(LINE_SIZE) && !req_we)    seen_rd = 1'b1;
                if (req_size != 3'(LINE_SIZE) && req_we)     seen_wr = 1'b1;
                if (answer)                                  seen_overlap = 1'b1;
            end
            taken = take;
            if (cycle >= N_CYCLES && (!req_valid || take) && ans_due.size() == 0)
                break;
            if (cycle > N_CYCLES + 200)
                `DC_TEST_FAIL(model, $sformatf("ReqDataWidthDown %0d: no end", LINE_WORDS))
        end
        // The last answer and offer were taken at the edge after the loop: then quiet, while
        // the other checks run on.
        @(negedge clk);
        req_valid     = 1'b0;
        tgt_rsp_valid = 1'b0;
        if (rsp_due.size() != 0)
            `DC_TEST_FAIL(model, $sformatf("ReqDataWidthDown %0d: %0d answers owed at the end",
                                           LINE_WORDS, rsp_due.size()))
        // With one word a line is a word: no "line" kinds apart, no queue.
        if (!seen_line_rd || !seen_line_wr || !seen_cbo || !seen_overlap ||
            (LINE_WORDS > 1 && (!seen_rd || !seen_wr || !seen_blocked)))
            `DC_TEST_FAIL(cover, $sformatf(
                "ReqDataWidthDown %0d: line %b %b %b, word %b %b, blocked %b, overlap %b",
                LINE_WORDS, seen_line_rd, seen_line_wr, seen_cbo, seen_rd, seen_wr,
                seen_blocked, seen_overlap))
        done = 1'b1;
    end
endmodule

module TbReqDataWidthDown;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_2, done_4, done_1;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbReqDataWidthDownCheck #(.LINE_WORDS(2), .PENDING_WIDTH(1)) u_check_2(.clk, .rst_n,
                                                                         .done(done_2));
    TbReqDataWidthDownCheck #(.LINE_WORDS(4), .PENDING_WIDTH(2)) u_check_4(.clk, .rst_n,
                                                                         .done(done_4));
    TbReqDataWidthDownCheck #(.LINE_WORDS(1), .PENDING_WIDTH(1)) u_check_1(.clk, .rst_n,
                                                                         .done(done_1));

    initial begin
        wait (done_2 && done_4 && done_1);
        $display("PASS");
        $finish;
    end
endmodule
