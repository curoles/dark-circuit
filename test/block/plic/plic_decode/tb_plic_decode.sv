/* Test of PlicDecode, behave or struct version.
 *
 * Model: PlicPkg's decode() (tested against the spec's map by block_plic_pkg), its register
 * turned into the one select it must be; every select is compared, so a second select or a
 * missing one fails. Three PLICs: 31 sources and 2 contexts (one word of bits per ID), 32
 * sources and 1 context (two words), 100 sources and 5 contexts. Addresses: every register
 * and the address after the last of each kind (a source, a word, a context beyond them),
 * then random ones near the registers and anywhere: 2000 on Verilator, 300 on Icarus; the
 * two low bits random (they must not matter). Every select must have been 1 (check named
 * cover). Checks named model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbPlicDecodeCheck #(
    parameter N_SOURCES  = 31,
    parameter N_CONTEXTS = 1
)(
    output logic done
);
    import PlicPkg::*;
`ifdef VERILATOR
    localparam N_RANDOM = 2000;
`else
    localparam N_RANDOM = 300;
`endif
    localparam W    = id_words(N_SOURCES);
    localparam NSEL = N_SOURCES + 1 + W + N_CONTEXTS * W + 2 * N_CONTEXTS;  // all selects
    localparam PRI0 = W + N_CONTEXTS * W + 2 * N_CONTEXTS;  // the bit of sel_priority[0]

    logic [ADDR_BITS-1:2]           addr;
    wire  [N_SOURCES:0]             sel_priority;
    wire  [W-1:0]                   sel_pending;
    wire  [N_CONTEXTS-1:0][W-1:0]   sel_enable;
    wire  [N_CONTEXTS-1:0]          sel_threshold;
    wire  [N_CONTEXTS-1:0]          sel_claim;
    logic [NSEL-1:0]                seen;   // selects that have been 1
    integer                         seed;

    PlicDecode #(.N_SOURCES(N_SOURCES), .N_CONTEXTS(N_CONTEXTS)) u_plic_decode(
        .addr, .sel_priority, .sel_pending, .sel_enable, .sel_threshold, .sel_claim);

    // The selects of the register decode() finds at byte address a, in the ports' order.
    function automatic logic [NSEL-1:0] expected(input logic [ADDR_BITS-1:0] a);
        reg_sel_t                    r;
        logic [N_SOURCES:0]          pri;
        logic [W-1:0]                pend;
        logic [N_CONTEXTS*W-1:0]     en;    // flat: bit c * W + w, as sel_enable
        logic [N_CONTEXTS-1:0]       thr, claim;
        r    = decode(a, N_SOURCES, N_CONTEXTS);
        pri  = '0;
        pend = '0;
        en   = '0;
        thr  = '0;
        claim = '0;
        case (r.kind)
            REG_PRIORITY:  pri[int'(r.index)] = 1'b1;
            REG_PENDING:   pend[int'(r.index)] = 1'b1;
            REG_ENABLE:    en[int'(r.ctx) * W + int'(r.index)] = 1'b1;
            REG_THRESHOLD: thr[int'(r.ctx)] = 1'b1;
            REG_CLAIM:     claim[int'(r.ctx)] = 1'b1;
            default: ;
        endcase
        return {pri, pend, en, thr, claim};
    endfunction

    // Byte address a (below 2**ADDR_BITS: the bits above are not used), its two low bits
    // random.
    /* verilator lint_off UNUSEDSIGNAL */
    task automatic check(input int a);
    /* verilator lint_on UNUSEDSIGNAL */
        logic [ADDR_BITS-1:0] ba;
        logic [NSEL-1:0]      got, exp;
        ba   = ADDR_BITS'(a) | ADDR_BITS'({$random(seed)} % 4);
        addr = ba[ADDR_BITS-1:2];
        #1;
        got  = {sel_priority, sel_pending, sel_enable, sel_threshold, sel_claim};
        exp  = expected(ba);
        if (got !== exp)
            `DC_TEST_FAIL(model, $sformatf({
                "PlicDecode %0d sources, %0d contexts, address %h: %b, expected %b"},
                N_SOURCES, N_CONTEXTS, ba, got, exp))
        seen = seen | got;
    endtask

    initial begin
        int c, kind;
        done = 1'b0;
        seen = '0;
        seed = N_SOURCES * 16 + N_CONTEXTS;
        for (int k = 0; k <= N_SOURCES + 1; k++)
            check(PRIORITY_BASE + 4 * k);
        for (int w = 0; w <= W; w++)
            check(PENDING_BASE + 4 * w);
        for (c = 0; c <= N_CONTEXTS; c++) begin
            for (int w = 0; w <= W; w++)
                check(ENABLE_BASE + ENABLE_STRIDE * c + 4 * w);
            check(CONTEXT_BASE + CONTEXT_STRIDE * c + THRESHOLD);
            check(CONTEXT_BASE + CONTEXT_STRIDE * c + CLAIM_COMPLETE);
            check(CONTEXT_BASE + CONTEXT_STRIDE * c + CLAIM_COMPLETE + 4);
        end
        repeat (N_RANDOM) begin
            kind = {$random(seed)} % 5;
            c    = {$random(seed)} % (N_CONTEXTS + 1);
            case (kind)
                0: check(PRIORITY_BASE + 4 * ({$random(seed)} % (N_SOURCES + 2)));
                1: check(PENDING_BASE + 4 * ({$random(seed)} % (W + 1)));
                2: check(ENABLE_BASE + ENABLE_STRIDE * c + 4 * ({$random(seed)} % 32));
                3: check(CONTEXT_BASE + CONTEXT_STRIDE * c + 4 * ({$random(seed)} % 4));
                default: check({$random(seed)} % (1 << ADDR_BITS));
            endcase
        end
        // Every select but the one of source 0 (reserved).
        if (seen !== ~(NSEL'(1) << PRI0))
            `DC_TEST_FAIL(cover, $sformatf("PlicDecode %0d sources, %0d contexts: selects seen %b",
                                           N_SOURCES, N_CONTEXTS, seen))
        done = 1'b1;
    end
endmodule

module TbPlicDecode;
    `DC_TEST_MUTANT_HOOK(top)

    wire done_31_2, done_32_1, done_100_5;

    TbPlicDecodeCheck #(.N_SOURCES(31),  .N_CONTEXTS(2)) u_check_31_2(.done(done_31_2));
    TbPlicDecodeCheck #(.N_SOURCES(32),  .N_CONTEXTS(1)) u_check_32_1(.done(done_32_1));
    TbPlicDecodeCheck #(.N_SOURCES(100), .N_CONTEXTS(5)) u_check_100_5(.done(done_100_5));

    initial begin
        wait (done_31_2 && done_32_1 && done_100_5);
        $display("PASS");
        $finish;
    end
endmodule
