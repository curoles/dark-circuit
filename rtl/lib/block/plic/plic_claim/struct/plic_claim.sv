/* PLIC claim and complete: what the contexts claim and complete, turned into one pulse per
 * source for its gateway; made of blocks and gates.
 *
 * Same ports and behavior as the behave version (see there). Per context two Decoders turn
 * the claimed and the completed ID into one-hot vectors of 2**IDW bits (only bits 1 to
 * N_SOURCES are used: bit 0 is ID 0, the bits above N_SOURCES IDs no source has); the
 * complete vector is And-ed with the context's enables. Per source an OrReduce over the
 * contexts gives claim[k] and complete[k]; bit 0 is 0.
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

    localparam NDEC = 1 << IDW;     // outputs of a Decoder

    // One-hot per context; bit 0 and the bits above N_SOURCES are not used.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [N_CONTEXTS-1:0][NDEC-1:0] claim_dec;
    wire [N_CONTEXTS-1:0][NDEC-1:0] complete_dec;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/plic/claim
    for (genvar c = 0; c < N_CONTEXTS; c++) begin: g_context
        Decoder #(.SIZE(IDW)) u_decoder_claim(
            .in(claim_id[c]), .en(claim_en[c]), .out(claim_dec[c]));
        Decoder #(.SIZE(IDW)) u_decoder_complete(
            .in(complete_id[c]), .en(complete_en[c]), .out(complete_dec[c]));
    end

    assign claim[0]    = 1'b0;
    assign complete[0] = 1'b0;
    for (genvar k = 1; k <= N_SOURCES; k++) begin: g_source
        wire [N_CONTEXTS-1:0] claims;       // claim of source k by context c
        wire [N_CONTEXTS-1:0] completes;    // complete of source k by context c, enabled
        for (genvar c = 0; c < N_CONTEXTS; c++) begin: g_context
            assign claims[c] = claim_dec[c][k];
            And2 #(1) u_and2(.in1(complete_dec[c][k]), .in2(ie[c][k]), .out(completes[c]));
        end
        OrReduce #(N_CONTEXTS) u_or_reduce_claim(.in(claims), .out(claim[k]));
        OrReduce #(N_CONTEXTS) u_or_reduce_complete(.in(completes), .out(complete[k]));
    end

endmodule
