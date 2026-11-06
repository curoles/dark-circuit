/* PLIC decode: which register of the PLIC an address is, as one select per register.
 *
 * The register map is PlicPkg's (the spec's). addr is the address of a word, bits 25 to 2 of
 * the byte offset from the PLIC's base: the two low bits select a byte, which the register
 * port's strobes do. When the address is a register of this PLIC (N_SOURCES sources,
 * N_CONTEXTS contexts) exactly its select is 1; when it is reserved none is. Only the
 * address: a write enable is a select and the access's write, a read takes the selected
 * register; the caller does that. Combinational.
 *
 *   addr --> PlicPkg::decode --> kind, ctx, index --+--> sel_priority[k]    k = 1 .. N_SOURCES
 *                                                   +--> sel_pending[w]     w = 0 .. W - 1
 *                                                   +--> sel_enable[c][w]   c = 0 .. N_CONTEXTS-1
 *                                                   +--> sel_threshold[c]
 *                                                   +--> sel_claim[c]
 *
 * W = PlicPkg::id_words(N_SOURCES), the words of one bit per ID 0 to N_SOURCES. Selects of
 * sources are indexed by source ID like the PLIC's other vectors: sel_priority[0] is 0.
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

    PlicPkg::reg_sel_t r;   // the register the address is

    // @kb: rtl/lib/block/plic/decode
    assign r = PlicPkg::decode({addr, 2'b00}, N_SOURCES, N_CONTEXTS);

    for (genvar k = 0; k <= N_SOURCES; k++) begin: g_priority
        assign sel_priority[k] = r.kind == PlicPkg::REG_PRIORITY && int'(r.index) == k;
    end
    for (genvar w = 0; w < W; w++) begin: g_pending
        assign sel_pending[w] = r.kind == PlicPkg::REG_PENDING && int'(r.index) == w;
    end
    for (genvar c = 0; c < N_CONTEXTS; c++) begin: g_context
        for (genvar w = 0; w < W; w++) begin: g_enable
            assign sel_enable[c][w] = r.kind == PlicPkg::REG_ENABLE && int'(r.ctx) == c &&
                                      int'(r.index) == w;
        end
        assign sel_threshold[c] = r.kind == PlicPkg::REG_THRESHOLD && int'(r.ctx) == c;
        assign sel_claim[c]     = r.kind == PlicPkg::REG_CLAIM && int'(r.ctx) == c;
    end

endmodule
