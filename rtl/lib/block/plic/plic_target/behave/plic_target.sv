/* PLIC target: one interrupt context (a hart in one privilege mode); its notification (EIP)
 * and the ID a claim gets (RISC-V PLIC spec, "Interrupt Notifications", "Interrupt Claim
 * Process").
 *
 * Sources have the IDs 1 to N_SOURCES; ID 0 means "no interrupt" and no source has it. The
 * vectors are indexed by ID, bit 0 is not used. A source is eligible for this context when it
 * is pending (ip), enabled for the context (ie) and its priority (prio, PRIO_WIDTH bits) is
 * not 0: priority 0 means never interrupt. Of the eligible sources, the one of the highest
 * priority wins, the lowest ID of equal ones (ArgMaxTree). Both outputs are registered, one
 * clock after the inputs:
 * - eip, the external interrupt pending of the context (to the hart's mip.MEIP or SEIP): the
 *   winner's priority is above the context's threshold;
 * - claim_id, what a claim of the context returns: the winner's ID, 0 if no source is
 *   eligible. Not gated by the threshold: the spec, "the claim operation is not affected by
 *   the setting of the priority threshold register".
 *
 *   ip, ie, prio --> eligible (ip & ie & prio != 0) --> ArgMaxTree --> prio > threshold --> eip
 *                                                           |  ID ----------------> claim_id
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module PlicTarget #(
    parameter  N_SOURCES  = 31,                     // sources, IDs 1 to N_SOURCES
    parameter  PRIO_WIDTH = 3,                      // bits of a priority
    localparam IDW        = $clog2(N_SOURCES + 1)   // bits of an ID
)(
    input  wire                                 clk,
    input  wire                                 rst_n,      // synchronous reset, active low
    // Bit or entry 0 is not used: no source has ID 0.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [N_SOURCES:0]                   ip,         // pending, by source ID
    input  wire [N_SOURCES:0]                   ie,         // enabled for this context
    input  wire [N_SOURCES:0][PRIO_WIDTH-1:0]   prio,       // priority of each source
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [PRIO_WIDTH-1:0]                threshold,  // of this context
    output logic                                eip,        // notification to the hart
    output logic [IDW-1:0]                      claim_id    // the ID a claim gets, 0 if none
);
    `DC_STATIC_ASSERT(a_sizes, N_SOURCES >= 1 && PRIO_WIDTH >= 1)

    // Eligible: pending, enabled and of a priority above 0; never ID 0.
    function automatic [N_SOURCES:0] eligible_of(input [N_SOURCES:0] p, input [N_SOURCES:0] e,
                                                 input [N_SOURCES:0][PRIO_WIDTH-1:0] pr);
        logic [N_SOURCES:0] el;
        el = '0;
        for (int k = 1; k <= N_SOURCES; k++)
            el[k] = p[k] && e[k] && pr[k] != '0;
        return el;
    endfunction

    logic [N_SOURCES:0]    eligible;
    // With no eligible source best_prio is 0, never above the threshold: eip needs no valid.
    /* verilator lint_off UNUSEDSIGNAL */
    logic                  best_valid;  // some source is eligible
    /* verilator lint_on UNUSEDSIGNAL */
    logic [PRIO_WIDTH-1:0] best_prio;   // the winner's priority, 0 if none
    logic [IDW-1:0]        best_id;     // and its ID, 0 if none

    assign eligible = eligible_of(ip, ie, prio);

    // @kb: rtl/lib/block/plic/target
    ArgMaxTree #(.N(N_SOURCES + 1), .WIDTH(PRIO_WIDTH)) u_arg_max_tree(
        .values(prio), .valid(eligible),
        .max_valid(best_valid), .max_value(best_prio), .max_index(best_id));

    always_ff @(posedge clk)
        if (!rst_n) begin
            eip      <= 1'b0;
            claim_id <= '0;
        end else begin
            eip      <= best_prio > threshold;
            claim_id <= best_id;
        end

    // A notification has a source to claim.
    `DC_ASSERT(a_eip_has_id, !eip || claim_id != '0)

endmodule
