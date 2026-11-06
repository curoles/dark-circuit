/* PLIC claim and complete: what the contexts claim and complete, turned into one pulse per
 * source for its gateway (RISC-V PLIC spec, "Interrupt Claim Process", "Interrupt
 * Completion"); purely combinational.
 *
 * Per context c: claim_en[c] = 1 when its claim/complete register is read now (a claim, once
 * per read the register port takes), claim_id[c] the ID that claim gets (PlicTarget's
 * registered claim ID); complete_en[c] = 1 when the register is written now, with the ID
 * complete_id[c]; ie[c] the context's enables. Out, per source ID (bit 0, no source, is 0):
 * - claim[k]: some context claims ID k now: the gateway clears k's pending bit;
 * - complete[k]: some context completes ID k now, and k is enabled for that context; the
 *   spec: "if the completion ID does not match an interrupt source that is currently
 *   enabled for the target, the completion is silently ignored". The ID need not be the one
 *   the context claimed (the spec does not check it).
 * A claim of ID 0 (nothing to claim), and a complete of 0 or of an ID above N_SOURCES, give
 * nothing. Several contexts in one cycle are ORed per source.
 *
 * Not here: a second claim must not see a claim ID that an earlier claim of the same source
 * has not cleared yet (the claim ID is registered: two clocks after a claim it shows the
 * cleared pending bit); whoever takes the claim reads makes the next one wait (kb
 * rtl/lib/block/plic/claim).
 *
 *   claim_en[c], claim_id[c] ---------> Decoder --+--> OR over c --> claim[k]
 *   complete_en[c], complete_id[c] ---> Decoder --+--> & ie[c] --> OR over c --> complete[k]
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module PlicClaim #(
    parameter  N_SOURCES  = 31,                     // sources, IDs 1 to N_SOURCES
    parameter  N_CONTEXTS = 1,                      // targets
    localparam IDW        = $clog2(N_SOURCES + 1)   // bits of an ID
)(
    input  wire [N_CONTEXTS-1:0]                claim_en,       // context c claims now
    input  wire [N_CONTEXTS-1:0][IDW-1:0]       claim_id,       // the ID its claim gets
    input  wire [N_CONTEXTS-1:0]                complete_en,    // context c completes now
    input  wire [N_CONTEXTS-1:0][IDW-1:0]       complete_id,    // the ID it completes
    // Bit 0 of every context is not used: no source has ID 0.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [N_CONTEXTS-1:0][N_SOURCES:0]   ie,             // enables of each context
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [N_SOURCES:0]                   claim,          // source k is claimed now
    output wire [N_SOURCES:0]                   complete        // source k completes now
);
    `DC_STATIC_ASSERT(a_sizes, N_SOURCES >= 1 && N_CONTEXTS >= 1)

    // {complete, claim} per source; source 0 never.
    function automatic [2*N_SOURCES+1:0] pulses(
            input [N_CONTEXTS-1:0] cl_en, input [N_CONTEXTS-1:0][IDW-1:0] cl_id,
            input [N_CONTEXTS-1:0] co_en, input [N_CONTEXTS-1:0][IDW-1:0] co_id,
            input [N_CONTEXTS-1:0][N_SOURCES:0] en);
        logic [N_SOURCES:0] cl;
        logic [N_SOURCES:0] co;
        logic [N_SOURCES:0] row;    // en[c]: Icarus does not take en[c][k] with both variable
        cl = '0;
        co = '0;
        for (int c = 0; c < N_CONTEXTS; c++) begin
            row = en[c];
            for (int k = 1; k <= N_SOURCES; k++) begin
                if (cl_en[c] && int'(cl_id[c]) == k)
                    cl[k] = 1'b1;
                if (co_en[c] && int'(co_id[c]) == k && row[k])
                    co[k] = 1'b1;
            end
        end
        return {co, cl};
    endfunction

    // @kb: rtl/lib/block/plic/claim
    assign {complete, claim} = pulses(claim_en, claim_id, complete_en, complete_id, ie);

endmodule
