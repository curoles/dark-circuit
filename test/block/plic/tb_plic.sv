/* Test of Plic, the whole PLIC, built with the behave or the struct library.
 *
 * The testbench is the software and the devices: it reads and writes the registers through
 * the register port, one request at a time, each offered right after the one before was
 * taken (so a request follows a claim at once and must wait), and drives src.
 *
 * Registers: random reads and writes (random data and strobes) of every register, of the
 * address after the last of each kind and of any address, against a model of the registers
 * (PlicPkg's decode() tells which; priorities and thresholds PRIO_WIDTH bits, enables bit 0
 * reads 0, pending 0 with no source, a claim reads 0); 600 requests; eip stays 0. Every kind
 * must have been read and written, and a write of some bytes only must have happened (checks
 * named cover). Verilator only (user: too long on Icarus; the parts' tests run on both).
 *
 * Interrupts, as software does it (checks named model):
 * - a level source: pending, eip, the claim gets it, eip falls, a complete while src is
 *   still 1 makes it pending again;
 * - three sources: the claims, one right after the other, get them by priority, the lower
 *   ID of a tie first, then 0 (a claim never gets a source twice);
 * - eip only above the threshold, the claim not gated by it;
 * - priority 0: pending but never eip or claim;
 * - a complete ignored when the source is not enabled for the context or the ID's byte is
 *   not written;
 * - an edge source (EDGE_LAST): an edge while it is active is lost;
 * - two contexts (N_CONTEXTS > 1) with the same source: one claim gets it, the other 0.
 * Two PLICs: 5 sources, 2 contexts, priorities of 3 bits, source 5 edge triggered; 33
 * sources (two words of bits), 1 context, priorities of 2 bits, ADDR_WIDTH 22. Stops at the
 * first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbPlicCheck #(
    parameter N_SOURCES  = 5,
    parameter N_CONTEXTS = 2,
    parameter PRIO_WIDTH = 3,
    parameter EDGE_LAST  = 1,               // source N_SOURCES is edge triggered
    parameter ADDR_WIDTH = 26
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
    import PlicPkg::*;
    localparam N_REQUESTS = 600;
    localparam W    = id_words(N_SOURCES);
    localparam PMAX = (1 << PRIO_WIDTH) - 1;
    localparam LAST = N_SOURCES;
    localparam CL   = N_CONTEXTS - 1;       // the last context
    localparam [N_SOURCES:1] EDGE = EDGE_LAST ? (N_SOURCES)'(1) << (N_SOURCES - 1) : '0;

    typedef logic [31:0] word_t;

    logic [N_SOURCES:1]    src;
    wire  [N_CONTEXTS-1:0] eip;
    logic                  req_valid;
    wire                   req_ready;
    logic                  req_we;
    logic [ADDR_WIDTH-1:0] req_addr;
    word_t                 req_wdata;
    logic [3:0]            req_wstrb;
    wire                   rsp_valid;
    wire  [31:0]           rsp_rdata;
    integer                seed;

    // The registers' model.
    logic [PRIO_WIDTH-1:0] m_prio [N_SOURCES+1];    // [0]: ID 0, stays 0
    logic [N_SOURCES:0]    m_ie [N_CONTEXTS];       // bit 0 stays 0
    logic [PRIO_WIDTH-1:0] m_thr [N_CONTEXTS];
    logic seen_wr_prio, seen_wr_en, seen_wr_thr, seen_rd_prio, seen_rd_pend, seen_rd_en,
          seen_rd_thr, seen_rd_claim, seen_rd_none, seen_part;

    Plic #(.N_SOURCES(N_SOURCES), .N_CONTEXTS(N_CONTEXTS), .PRIO_WIDTH(PRIO_WIDTH),
           .EDGE_TRIGGERED(EDGE), .ADDR_WIDTH(ADDR_WIDTH)) u_plic(
        .clk, .rst_n, .src, .eip, .req_valid, .req_ready, .req_we, .req_addr, .req_wdata,
        .req_wstrb, .rsp_valid, .rsp_rdata);

    function automatic string name();
        return $sformatf("Plic %0d sources, %0d contexts", N_SOURCES, N_CONTEXTS);
    endfunction

    // old with the bytes of new where strb is 1.
    function automatic word_t merge(input word_t old, input word_t new_w, input logic [3:0] strb);
        word_t w;
        w = old;
        for (int b = 0; b < 4; b++)
            if (strb[b])
                w[8*b +: 8] = new_w[8*b +: 8];
        return w;
    endfunction

    // The helpers below take addresses (below 2**ADDR_WIDTH) and contexts (below N_CONTEXTS)
    // as int: the bits above are not used.
    /* verilator lint_off UNUSEDSIGNAL */

    // One request, offered from now until it is taken; returns after the edge that takes it.
    task automatic request(input logic we, input int a, input word_t wd, input logic [3:0] strb);
        req_valid = 1'b1;
        req_we    = we;
        req_addr  = ADDR_WIDTH'(a);
        req_wdata = wd;
        req_wstrb = strb;
        @(negedge clk);
        while (!req_ready)
            @(negedge clk);
        @(posedge clk);
        #1;
        req_valid = 1'b0;
    endtask

    task automatic rd(input int a, output word_t d);
        request(1'b0, a, word_t'($random(seed)), 4'($random(seed)));
        if (rsp_valid !== 1'b1)
            `DC_TEST_FAIL(model, $sformatf("%s: no answer to the read of %h", name(), a))
        d = rsp_rdata;
    endtask

    task automatic wr(input int a, input word_t d, input logic [3:0] strb);
        request(1'b1, a, d, strb);
    endtask

    task automatic expect_rd(input int a, input word_t exp, input string what);
        word_t d;
        rd(a, d);
        if (d !== exp)
            `DC_TEST_FAIL(model, $sformatf("%s: %s, read %h of %h, expected %h",
                                           name(), what, d, a, exp))
    endtask

    task automatic settle();    // the gateways and the targets follow
        repeat (3) @(posedge clk);
        #1;
    endtask

    task automatic expect_eip(input int c, input logic exp, input string what);
        if (eip[c] !== exp)
            `DC_TEST_FAIL(model, $sformatf("%s: %s, eip[%0d] %b", name(), what, c, eip[c]))
    endtask

    // Word w of the enables of context c in the model.
    function automatic word_t ie_word(input int c, input int w);
        logic [N_SOURCES:0] row;
        word_t              v;
        row = m_ie[c];
        v   = '0;
        for (int b = 0; b < 32; b++)
            if (32 * w + b <= N_SOURCES)
                v[b] = row[32 * w + b];
        return v;
    endfunction

    function automatic int claim_addr(input int c);
        return CONTEXT_BASE + CONTEXT_STRIDE * c + CLAIM_COMPLETE;
    endfunction

    // The model after a write of d with strb to byte address a.
    task automatic model_write(input int a, input word_t d, input logic [3:0] strb);
        reg_sel_t           r;
        int                 c, i;   // r's context and index
        word_t              v;
        logic [N_SOURCES:0] row;
        r = decode(ADDR_BITS'(a), N_SOURCES, N_CONTEXTS);
        c = int'(r.ctx);
        i = int'(r.index);
        case (r.kind)
            REG_PRIORITY: begin
                m_prio[i]    = PRIO_WIDTH'(merge(word_t'(m_prio[i]), d, strb));
                seen_wr_prio = 1'b1;
            end
            REG_ENABLE: begin
                v   = merge(ie_word(c, i), d, strb);
                row = m_ie[c];
                for (int b = 0; b < 32; b++)
                    if (32 * i + b <= N_SOURCES)
                        row[32 * i + b] = v[b];
                row[0]     = 1'b0;
                m_ie[c]    = row;
                seen_wr_en = 1'b1;
            end
            REG_THRESHOLD: begin
                m_thr[c]    = PRIO_WIDTH'(merge(word_t'(m_thr[c]), d, strb));
                seen_wr_thr = 1'b1;
            end
            default: ;  // pending: read only; a complete of nothing active; reserved
        endcase
    endtask

    // What a read of byte address a gives in the model, no source pending.
    function automatic word_t model_read(input int a);
        reg_sel_t r;
        int       c, i;     // r's context and index
        r = decode(ADDR_BITS'(a), N_SOURCES, N_CONTEXTS);
        c = int'(r.ctx);
        i = int'(r.index);
        case (r.kind)
            REG_PRIORITY:  begin seen_rd_prio  = 1'b1; return word_t'(m_prio[i]); end
            REG_PENDING:   begin seen_rd_pend  = 1'b1; return '0; end
            REG_ENABLE:    begin seen_rd_en    = 1'b1; return ie_word(c, i); end
            REG_THRESHOLD: begin seen_rd_thr   = 1'b1; return word_t'(m_thr[c]); end
            REG_CLAIM:     begin seen_rd_claim = 1'b1; return '0; end
            default:       begin seen_rd_none  = 1'b1; return '0; end
        endcase
    endfunction

    /* verilator lint_on UNUSEDSIGNAL */

    // A random address near the registers, or any.
    function automatic int random_addr();
        int c;
        c = {$random(seed)} % (N_CONTEXTS + 1);
        case ({$random(seed)} % 5)
            0:       return PRIORITY_BASE + 4 * ({$random(seed)} % (N_SOURCES + 2));
            1:       return PENDING_BASE + 4 * ({$random(seed)} % (W + 1));
            2:       return ENABLE_BASE + ENABLE_STRIDE * c + 4 * ({$random(seed)} % (W + 1));
            3:       return CONTEXT_BASE + CONTEXT_STRIDE * c + 4 * ({$random(seed)} % 3);
            default: return {$random(seed)} % (1 << ADDR_WIDTH);
        endcase
    endfunction

    // Software's view of the interrupts.
    task automatic set_prio(input int k, input int p);
        wr(PRIORITY_BASE + 4 * k, word_t'(p), 4'hf);
    endtask

    task automatic set_ie(input int c, input int k, input logic v);
        logic [N_SOURCES:0] row;
        row    = m_ie[c];
        row[k] = v;
        m_ie[c] = row;
        wr(ENABLE_BASE + ENABLE_STRIDE * c + 4 * (k / 32), ie_word(c, k / 32), 4'hf);
    endtask

    task automatic set_thr(input int c, input int t);
        wr(CONTEXT_BASE + CONTEXT_STRIDE * c + THRESHOLD, word_t'(t), 4'hf);
    endtask

    task automatic expect_claim(input int c, input int id, input string what);
        expect_rd(claim_addr(c), word_t'(id), what);
    endtask

    task automatic complete(input int c, input int id, input logic [3:0] strb);
        wr(claim_addr(c), word_t'(id), strb);
    endtask

    task automatic expect_pending(input int k, input logic exp, input string what);
        word_t d;
        rd(PENDING_BASE + 4 * (k / 32), d);
        if (d[k % 32] !== exp)
            `DC_TEST_FAIL(model, $sformatf("%s: %s, pending of %0d is %b",
                                           name(), what, k, d[k % 32]))
    endtask

    task automatic pulse(input int k);  // an edge of source k, one clock at 1
        src[k] = 1'b1;
        @(posedge clk);
        #1;
        src[k] = 1'b0;
    endtask

    `DC_STATIC_ASSERT(a_three, N_SOURCES >= 3)

    initial begin
        int         a;
        word_t      d;
        logic [3:0] strb;
        done      = 1'b0;
        seed      = N_SOURCES * 16 + N_CONTEXTS;
        src       = '0;
        req_valid = 1'b0;
        req_we    = 1'b0;
        req_addr  = '0;
        req_wdata = '0;
        req_wstrb = '0;
        {seen_wr_prio, seen_wr_en, seen_wr_thr, seen_rd_prio, seen_rd_pend, seen_rd_en,
         seen_rd_thr, seen_rd_claim, seen_rd_none, seen_part} = '0;
        foreach (m_prio[k])
            m_prio[k] = '0;
        foreach (m_ie[c])
            m_ie[c] = '0;
        foreach (m_thr[c])
            m_thr[c] = '0;
        @(posedge rst_n);
        @(posedge clk);
        #1;

        // Registers.
        repeat (N_REQUESTS) begin
            a = random_addr();
            if ($random(seed) % 2 == 0) begin
                expect_rd(a, model_read(a), "register");
            end else begin
                d    = $random(seed);
                strb = ($random(seed) % 4 == 0) ? 4'($random(seed)) : 4'hf;
                if (strb != 4'hf && strb != 4'h0)
                    seen_part = 1'b1;
                wr(a, d, strb);
                model_write(a, d, strb);
            end
        end
        if (eip !== '0)
            `DC_TEST_FAIL(model, $sformatf("%s: eip %b with no source", name(), eip))
        if (!seen_wr_prio || !seen_wr_en || !seen_wr_thr || !seen_rd_prio || !seen_rd_pend ||
            !seen_rd_en || !seen_rd_thr || !seen_rd_claim || !seen_rd_none || !seen_part)
            `DC_TEST_FAIL(cover, $sformatf({
                "%s: written prio %b en %b thr %b, read prio %b pend %b en %b thr %b claim %b ",
                "none %b, part %b"}, name(), seen_wr_prio, seen_wr_en, seen_wr_thr,
                seen_rd_prio, seen_rd_pend, seen_rd_en, seen_rd_thr, seen_rd_claim,
                seen_rd_none, seen_part))

        // Interrupts: every source priority 1 and disabled, thresholds 0.
        for (int k = 1; k <= N_SOURCES; k++)
            set_prio(k, 1);
        for (int c = 0; c < N_CONTEXTS; c++) begin
            for (int k = 1; k <= N_SOURCES; k++)
                set_ie(c, k, 1'b0);
            set_thr(c, 0);
        end

        // A level source.
        set_ie(0, 1, 1'b1);
        src[1] = 1'b1;
        settle();
        expect_pending(1, 1'b1, "level source raised");
        expect_eip(0, 1'b1, "level source raised");
        expect_claim(0, 1, "level source claimed");
        settle();
        expect_pending(1, 1'b0, "claimed");
        expect_eip(0, 1'b0, "claimed");
        complete(0, 1, 4'hf);
        settle();
        expect_pending(1, 1'b1, "completed, src still 1");
        expect_claim(0, 1, "claimed again");
        src[1] = 1'b0;
        complete(0, 1, 4'hf);
        settle();
        expect_pending(1, 1'b0, "completed, src 0");
        expect_eip(0, 1'b0, "completed, src 0");
        expect_claim(0, 0, "nothing pending");

        // Three sources: by priority, the lower ID of a tie first; claims back to back.
        set_prio(2, PMAX);
        set_prio(LAST, PMAX);
        set_ie(0, 2, 1'b1);
        set_ie(0, LAST, 1'b1);
        src[1] = 1'b1;
        src[2] = 1'b1;
        if (EDGE_LAST) pulse(LAST); else src[LAST] = 1'b1;
        settle();
        expect_claim(0, 2, "first of three");
        expect_claim(0, LAST, "second of three");
        expect_claim(0, 1, "third of three");
        expect_claim(0, 0, "none of three left");
        src = '0;
        complete(0, 2, 4'hf);
        complete(0, LAST, 4'hf);
        complete(0, 1, 4'hf);
        settle();
        expect_eip(0, 1'b0, "three completed");

        // The threshold gates eip, not the claim.
        set_thr(0, PMAX - 1);
        src[2] = 1'b1;
        settle();
        expect_eip(0, 1'b1, "priority above the threshold");
        set_thr(0, PMAX);
        settle();
        expect_eip(0, 1'b0, "priority at the threshold");
        expect_claim(0, 2, "claim at the threshold");
        src[2] = 1'b0;
        complete(0, 2, 4'hf);
        set_thr(0, 0);

        // Priority 0: never eligible.
        set_prio(1, 0);
        src[1] = 1'b1;
        settle();
        expect_pending(1, 1'b1, "priority 0 pending");
        expect_eip(0, 1'b0, "priority 0");
        expect_claim(0, 0, "priority 0 claimed");
        set_prio(1, 1);
        settle();
        expect_eip(0, 1'b1, "priority 1 again");
        expect_claim(0, 1, "priority 1 again");
        src[1] = 1'b0;
        complete(0, 1, 4'hf);

        // Completes ignored: the source not enabled, the ID's byte not written.
        src[2] = 1'b1;
        settle();
        expect_claim(0, 2, "to complete");
        set_ie(0, 2, 1'b0);
        complete(0, 2, 4'hf);
        set_ie(0, 2, 1'b1);
        settle();
        expect_pending(2, 1'b0, "complete of a disabled source ignored");
        complete(0, 2, 4'b1110);
        settle();
        expect_pending(2, 1'b0, "complete without the ID's byte ignored");
        complete(0, 2, 4'hf);
        settle();
        expect_pending(2, 1'b1, "complete taken");
        expect_claim(0, 2, "after the complete");
        src[2] = 1'b0;
        complete(0, 2, 4'hf);
        settle();

        // An edge source: an edge while it is active is lost.
        if (EDGE_LAST) begin
            pulse(LAST);
            settle();
            expect_pending(LAST, 1'b1, "edge");
            expect_claim(0, LAST, "edge claimed");
            pulse(LAST);
            settle();
            expect_pending(LAST, 1'b0, "edge while active");
            complete(0, LAST, 4'hf);
            settle();
            expect_pending(LAST, 1'b0, "the edge while active is lost");
            pulse(LAST);
            settle();
            expect_pending(LAST, 1'b1, "edge after the complete");
            expect_claim(0, LAST, "edge after the complete claimed");
            complete(0, LAST, 4'hf);
        end

        // Two contexts, one source: one claim gets it.
        if (N_CONTEXTS > 1) begin
            set_ie(CL, 1, 1'b1);
            src[1] = 1'b1;
            settle();
            expect_eip(0, 1'b1, "source of two contexts");
            expect_eip(CL, 1'b1, "source of two contexts");
            expect_claim(0, 1, "first context");
            expect_claim(CL, 0, "second context, right after");
            settle();
            expect_eip(0, 1'b0, "claimed by the first context");
            expect_eip(CL, 1'b0, "claimed by the first context");
            src[1] = 1'b0;
            complete(0, 1, 4'hf);
        end
        settle();
        done = 1'b1;
    end
endmodule

module TbPlic;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_5_2, done_33_1;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbPlicCheck #(.N_SOURCES(5), .N_CONTEXTS(2), .PRIO_WIDTH(3), .EDGE_LAST(1),
                  .ADDR_WIDTH(26)) u_check_5_2(.clk, .rst_n, .done(done_5_2));
    TbPlicCheck #(.N_SOURCES(33), .N_CONTEXTS(1), .PRIO_WIDTH(2), .EDGE_LAST(0),
                  .ADDR_WIDTH(22)) u_check_33_1(.clk, .rst_n, .done(done_33_1));

    initial begin
        wait (done_5_2 && done_33_1);
        $display("PASS");
        $finish;
    end
endmodule
