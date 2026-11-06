/* PLIC package: the register map of the RISC-V PLIC spec ("Memory Map") and its decode.
 *
 * Byte offsets from the PLIC's base; every register is 32 bits, an address selects the word
 * (its two low bits are ignored, the byte lanes are the register port's strobes):
 *
 *   0x000000 + 4 * k                 priority of source k (k = 0: reserved, no source)
 *   0x001000 + 4 * w                 pending bits of IDs 32w to 32w + 31 (read only)
 *   0x002000 + 0x80 * c + 4 * w      enable bits of IDs 32w to 32w + 31 for context c
 *   0x200000 + 0x1000 * c            priority threshold of context c
 *   0x200004 + 0x1000 * c            claim (read) / complete (write) of context c
 *
 * Every other address is reserved: it reads 0, a write to it is ignored. decode() tells
 * which register an address is for a PLIC of n_sources sources (IDs 1 to n_sources) and
 * n_contexts contexts, REG_NONE where that PLIC has none (a source or context beyond them,
 * a gap of the map). The spec's limits: 1023 sources, 15872 contexts; the map is 64 MiB.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package PlicPkg;

    /* verilator lint_off UNUSEDPARAM */
    localparam int MAX_SOURCES    = 1023;       // IDs 1 to 1023
    localparam int MAX_CONTEXTS   = 15872;
    localparam int ADDR_BITS      = 26;         // the map is 64 MiB
    localparam int CTX_BITS       = 14;         // a context number
    localparam int INDEX_BITS     = 10;         // a source ID, or a word of 32 sources

    localparam int PRIORITY_BASE  = 'h000000;   // + 4 * source ID
    localparam int PENDING_BASE   = 'h001000;   // + 4 * word
    localparam int ENABLE_BASE    = 'h002000;   // + ENABLE_STRIDE * context + 4 * word
    localparam int ENABLE_STRIDE  = 'h80;
    localparam int CONTEXT_BASE   = 'h200000;   // + CONTEXT_STRIDE * context
    localparam int CONTEXT_STRIDE = 'h1000;
    localparam int THRESHOLD      = 'h0;        // in the block of a context
    localparam int CLAIM_COMPLETE = 'h4;        // in the block of a context
    /* verilator lint_on UNUSEDPARAM */

    typedef enum logic [2:0] {
        REG_NONE,       // reserved: reads 0, a write is ignored
        REG_PRIORITY,   // index: the source ID
        REG_PENDING,    // index: the word of 32 IDs; read only
        REG_ENABLE,     // ctx, index: the word of 32 IDs
        REG_THRESHOLD,  // ctx
        REG_CLAIM       // ctx: a read claims, a write completes
    } reg_e;

    // Which register an address is.
    typedef struct packed {
        reg_e                  kind;
        logic [CTX_BITS-1:0]   ctx;     // context of an enable, threshold or claim register
        logic [INDEX_BITS-1:0] index;   // source ID of a priority, word of pending or enable
    } reg_sel_t;

    // Words of 32 bits that hold one bit per ID 0 to n_sources.
    function automatic int id_words(input int n_sources);
        return n_sources / 32 + 1;
    endfunction

    // The register at byte address a of a PLIC with n_sources and n_contexts. The two low bits
    // of a select a byte of the word: not used.
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic reg_sel_t decode(input logic [ADDR_BITS-1:0] a, input int n_sources,
                                        input int n_contexts);
    /* verilator lint_on UNUSEDSIGNAL */
        reg_sel_t r;
        int       off;      // the word's byte offset
        int       c;        // context
        int       in_blk;   // offset inside the block of a context
        r.kind  = REG_NONE;
        r.ctx   = '0;
        r.index = '0;
        off     = int'({a[ADDR_BITS-1:2], 2'b00});
        if (off < PENDING_BASE) begin
            if (off / 4 >= 1 && off / 4 <= n_sources) begin
                r.kind  = REG_PRIORITY;
                r.index = INDEX_BITS'(off / 4);
            end
        end else if (off < ENABLE_BASE) begin
            if ((off - PENDING_BASE) / 4 < id_words(n_sources)) begin
                r.kind  = REG_PENDING;
                r.index = INDEX_BITS'((off - PENDING_BASE) / 4);
            end
        end else if (off < CONTEXT_BASE) begin
            c      = (off - ENABLE_BASE) / ENABLE_STRIDE;
            in_blk = (off - ENABLE_BASE) % ENABLE_STRIDE;
            if (c < n_contexts && in_blk / 4 < id_words(n_sources)) begin
                r.kind  = REG_ENABLE;
                r.ctx   = CTX_BITS'(c);
                r.index = INDEX_BITS'(in_blk / 4);
            end
        end else begin
            c      = (off - CONTEXT_BASE) / CONTEXT_STRIDE;
            in_blk = (off - CONTEXT_BASE) % CONTEXT_STRIDE;
            // An if, not "? :": Icarus does not assign a conditional of enum items to an enum.
            if (c < n_contexts && in_blk == THRESHOLD) begin
                r.kind = REG_THRESHOLD;
                r.ctx  = CTX_BITS'(c);
            end else if (c < n_contexts && in_blk == CLAIM_COMPLETE) begin
                r.kind = REG_CLAIM;
                r.ctx  = CTX_BITS'(c);
            end
        end
        return r;
    endfunction

endpackage
