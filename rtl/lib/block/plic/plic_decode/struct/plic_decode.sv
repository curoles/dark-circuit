/* PLIC decode: which register of the PLIC an address is, as one select per register; made of
 * gates.
 *
 * Same ports and behavior as the behave version (see there). The map is made of blocks of
 * 4 KiB (the priorities, the pending words, the registers of a context) and of 128 bytes (the
 * enables of a context): the high bits of the address say which block, the low bits which
 * word in it. Per block a CmpEq of the high bits with the block's number; per word number a
 * CmpEq of the low bits, shared by the blocks of its size; a select is the And2 of the two.
 *
 *   addr[25:12] == block of the priorities ---------> in_priority --+
 *   addr[11:2]  == i, i = 0 .. N_SOURCES -----------> word_is[i] ---+-- And2 --> sel_priority[i]
 *   addr[25:12] == block of the pending words ------> in_pending, with word_is[w]
 *   addr[25:12] == block of context c --------------> in_context, with word_is[0], word_is[1]
 *   addr[25:7]  == enable block of context c -------> in_enable, with en_word_is[w]
 *   addr[6:2]   == w, w = 0 .. W - 1 ---------------> en_word_is[w]
 *
 * word_is[] goes up to N_SOURCES, the largest word number of a 4 KiB block: a priority; the
 * pending words (at most N_SOURCES + 1 bits, so fewer words) and the threshold and claim of a
 * context (words 0 and 1) take theirs from it.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module PlicDecode #(
    parameter  N_SOURCES  = 31,                             // sources, IDs 1 to N_SOURCES
    parameter  N_CONTEXTS = 1,                              // targets
    localparam W          = PlicPkg::id_words(N_SOURCES)    // words of bits per ID
)(
    input  wire [PlicPkg::ADDR_BITS-1:2]    addr,           // the word's address
    output wire [N_SOURCES:0]               sel_priority,   // priority of source k
    output wire [W-1:0]                     sel_pending,    // pending word w
    output wire [N_CONTEXTS-1:0][W-1:0]     sel_enable,     // enable word w of context c
    output wire [N_CONTEXTS-1:0]            sel_threshold,  // threshold of context c
    output wire [N_CONTEXTS-1:0]            sel_claim       // claim/complete of context c
);
    `DC_STATIC_ASSERT(a_sizes, N_SOURCES >= 1 && N_SOURCES <= PlicPkg::MAX_SOURCES &&
                      N_CONTEXTS >= 1 && N_CONTEXTS <= PlicPkg::MAX_CONTEXTS)

    localparam AW = PlicPkg::ADDR_BITS;
    localparam BB = $clog2(PlicPkg::CONTEXT_STRIDE);    // bits of an offset in a 4 KiB block
    localparam EB = $clog2(PlicPkg::ENABLE_STRIDE);     // in a context's enable block

    // The map's blocks are where the fields above assume them.
    `DC_STATIC_ASSERT(a_map, PlicPkg::CONTEXT_STRIDE == 1 << BB &&
                      PlicPkg::ENABLE_STRIDE == 1 << EB &&
                      PlicPkg::PENDING_BASE - PlicPkg::PRIORITY_BASE == 1 << BB &&
                      PlicPkg::ENABLE_BASE - PlicPkg::PENDING_BASE == 1 << BB)

    wire [N_SOURCES:0] word_is;     // the word in a 4 KiB block is i
    wire [W-1:0]       en_word_is;  // the word in an enable block is w
    wire               in_priority; // the address is in the block of the priorities
    wire               in_pending;  // in the block of the pending words

    // @kb: rtl/lib/block/plic/decode
    for (genvar i = 0; i <= N_SOURCES; i++) begin: g_word
        CmpEq #(BB - 2) u_cmp_eq(.in1(addr[BB-1:2]), .in2((BB - 2)'(i)), .eq(word_is[i]));
    end
    for (genvar w = 0; w < W; w++) begin: g_en_word
        CmpEq #(EB - 2) u_cmp_eq(.in1(addr[EB-1:2]), .in2((EB - 2)'(w)), .eq(en_word_is[w]));
    end

    CmpEq #(AW - BB) u_cmp_eq_priority(
        .in1(addr[AW-1:BB]), .in2((AW - BB)'(PlicPkg::PRIORITY_BASE >> BB)), .eq(in_priority));
    CmpEq #(AW - BB) u_cmp_eq_pending(
        .in1(addr[AW-1:BB]), .in2((AW - BB)'(PlicPkg::PENDING_BASE >> BB)), .eq(in_pending));

    assign sel_priority[0] = 1'b0;  // source 0: reserved
    for (genvar k = 1; k <= N_SOURCES; k++) begin: g_priority
        And2 #(1) u_and2(.in1(in_priority), .in2(word_is[k]), .out(sel_priority[k]));
    end
    for (genvar w = 0; w < W; w++) begin: g_pending
        And2 #(1) u_and2(.in1(in_pending), .in2(word_is[w]), .out(sel_pending[w]));
    end

    for (genvar c = 0; c < N_CONTEXTS; c++) begin: g_context
        localparam EN_BLOCK  = (PlicPkg::ENABLE_BASE + PlicPkg::ENABLE_STRIDE * c) >> EB;
        localparam CTX_BLOCK = (PlicPkg::CONTEXT_BASE + PlicPkg::CONTEXT_STRIDE * c) >> BB;
        wire in_enable;     // the address is in the enable block of context c
        wire in_context;    // in the block of context c
        CmpEq #(AW - EB) u_cmp_eq_enable(
            .in1(addr[AW-1:EB]), .in2((AW - EB)'(EN_BLOCK)), .eq(in_enable));
        CmpEq #(AW - BB) u_cmp_eq_context(
            .in1(addr[AW-1:BB]), .in2((AW - BB)'(CTX_BLOCK)), .eq(in_context));
        for (genvar w = 0; w < W; w++) begin: g_enable
            And2 #(1) u_and2(.in1(in_enable), .in2(en_word_is[w]), .out(sel_enable[c][w]));
        end
        And2 #(1) u_and2_threshold(
            .in1(in_context), .in2(word_is[PlicPkg::THRESHOLD / 4]), .out(sel_threshold[c]));
        And2 #(1) u_and2_claim(
            .in1(in_context), .in2(word_is[PlicPkg::CLAIM_COMPLETE / 4]), .out(sel_claim[c]));
    end

endmodule
