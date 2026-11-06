/* Test of PlicPkg's decode() against the memory map of the RISC-V PLIC spec.
 *
 * A table of addresses written from the spec's map (riscv-plic-spec, "Memory Map"), each
 * with the register it must be for three PLICs: 31 sources and 2 contexts, 32 sources and 1
 * context (a second word of bits), and the spec's largest, 1023 sources and 15872 contexts.
 * The cases: source 0 (reserved), the first and last source, the source after the last, an
 * address inside a word (low bits ignored), the pending words, enables of the first and last
 * context and word, the gap after the enables, threshold and claim of a context, the word
 * after the claim (reserved), a context beyond the last. Checks named model. Stops at the
 * first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbPlicPkg;
    import PlicPkg::*;
    `DC_TEST_MUTANT_HOOK(top)

    integer n;      // cases checked

    // decode(a) of a PLIC of ns sources and nc contexts must be kind, ctx, index.
    task automatic check(input int ns, input int nc, input int a, input reg_e kind,
                         input int ctx, input int index);
        reg_sel_t r;
        r = decode(ADDR_BITS'(a), ns, nc);
        if (r.kind !== kind || (kind != REG_NONE && (int'(r.ctx) !== ctx ||
                                                       int'(r.index) !== index)))
            `DC_TEST_FAIL(model, $sformatf({
                "PlicPkg decode(%h) of %0d sources, %0d contexts: ",
                "kind %0d ctx %0d index %0d, expected %0d %0d %0d"},
                a, ns, nc, r.kind, r.ctx, r.index, kind, ctx, index))
        n = n + 1;
    endtask

    initial begin
        n = 0;
        // 31 sources (one word of bits: IDs 0 to 31), 2 contexts.
        check(31, 2, 'h000000, REG_NONE,      0, 0);    // source 0: reserved
        check(31, 2, 'h000004, REG_PRIORITY,  0, 1);
        check(31, 2, 'h000006, REG_PRIORITY,  0, 1);    // inside the word
        check(31, 2, 'h00007c, REG_PRIORITY,  0, 31);
        check(31, 2, 'h000080, REG_NONE,      0, 0);    // source 32: none
        check(31, 2, 'h001000, REG_PENDING,   0, 0);
        check(31, 2, 'h001004, REG_NONE,      0, 0);    // a second word: none
        check(31, 2, 'h002000, REG_ENABLE,    0, 0);
        check(31, 2, 'h002004, REG_NONE,      0, 0);
        check(31, 2, 'h002080, REG_ENABLE,    1, 0);
        check(31, 2, 'h002100, REG_NONE,      0, 0);    // context 2: none
        check(31, 2, 'h200000, REG_THRESHOLD, 0, 0);
        check(31, 2, 'h200004, REG_CLAIM,     0, 0);
        check(31, 2, 'h200008, REG_NONE,      0, 0);    // reserved
        check(31, 2, 'h201000, REG_THRESHOLD, 1, 0);
        check(31, 2, 'h201004, REG_CLAIM,     1, 0);
        check(31, 2, 'h202000, REG_NONE,      0, 0);    // context 2: none
        check(31, 2, 'h3fff004, REG_NONE,     0, 0);
        // 32 sources: IDs 0 to 32 need two words of bits; 1 context.
        check(32, 1, 'h000080, REG_PRIORITY,  0, 32);
        check(32, 1, 'h001004, REG_PENDING,   0, 1);
        check(32, 1, 'h001008, REG_NONE,      0, 0);
        check(32, 1, 'h002004, REG_ENABLE,    0, 1);
        check(32, 1, 'h002080, REG_NONE,      0, 0);    // context 1: none
        check(32, 1, 'h201000, REG_NONE,      0, 0);
        // The spec's largest PLIC.
        check(1023, 15872, 'h000ffc, REG_PRIORITY,  0,     1023);
        check(1023, 15872, 'h00107c, REG_PENDING,   0,     31);
        check(1023, 15872, 'h001080, REG_NONE,      0,     0);  // after the pending words
        check(1023, 15872, 'h1f1f80, REG_ENABLE,    15871, 0);
        check(1023, 15872, 'h1f1ffc, REG_ENABLE,    15871, 31);
        check(1023, 15872, 'h1f2000, REG_NONE,      0,     0);  // the gap after the enables
        check(1023, 15872, 'h1ffffc, REG_NONE,      0,     0);
        check(1023, 15872, 'h3fff000, REG_THRESHOLD, 15871, 0);
        check(1023, 15872, 'h3fff004, REG_CLAIM,     15871, 0);
        check(1023, 15872, 'h3fffffc, REG_NONE,      0,     0);
        $display("PASS: %0d addresses", n);
        $finish;
    end
endmodule
