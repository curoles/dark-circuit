/* PLIC target: one interrupt context; its notification (EIP) and the ID a claim gets; made of
 * blocks, parts and gates.
 *
 * Same ports and behavior as the behave version (see there). Per source k (1 to N_SOURCES)
 * an OrReduce tells that its priority is not 0 and an And3 makes it eligible with ip and ie;
 * ID 0 is never eligible. An ArgMaxTree over IDs 0 to N_SOURCES gives the winner's priority
 * and ID. The winner's priority is above the threshold when best_prio + ~threshold carries
 * (a KoggeStoneAdder, as the nodes of ArgMaxTree). Two DffSyncRst register eip and claim_id.
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
    output wire                                 eip,        // notification to the hart
    output wire [IDW-1:0]                       claim_id    // the ID a claim gets, 0 if none
);
    `DC_STATIC_ASSERT(a_sizes, N_SOURCES >= 1 && PRIO_WIDTH >= 1)

    wire [N_SOURCES:0]    eligible;
    wire [PRIO_WIDTH-1:0] best_prio;    // the winner's priority, 0 if none
    wire [IDW-1:0]        best_id;      // and its ID, 0 if none
    wire [PRIO_WIDTH-1:0] threshold_n;
    wire                  above;        // best_prio > threshold: eip
    // With no eligible source best_prio is 0, never above the threshold: eip needs no valid.
    // Of best_prio - threshold - 1 only the carry out is used.
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  best_valid;   // some source is eligible
    wire [PRIO_WIDTH-1:0] diff;
    /* verilator lint_on UNUSEDSIGNAL */

    assign eligible[0] = 1'b0;
    for (genvar k = 1; k <= N_SOURCES; k++) begin: g_eligible
        wire prio_set;  // the priority of source k is not 0
        OrReduce #(PRIO_WIDTH) u_or_reduce(.in(prio[k]), .out(prio_set));
        And3 #(1) u_and3(.in1(ip[k]), .in2(ie[k]), .in3(prio_set), .out(eligible[k]));
    end

    // @kb: rtl/lib/block/plic/target
    ArgMaxTree #(.N(N_SOURCES + 1), .WIDTH(PRIO_WIDTH)) u_arg_max_tree(
        .values(prio), .valid(eligible),
        .max_valid(best_valid), .max_value(best_prio), .max_index(best_id));

    Inv #(PRIO_WIDTH) u_inv(.in(threshold), .out(threshold_n));
    KoggeStoneAdder #(PRIO_WIDTH) u_kogge_stone_adder(
        .in1(best_prio), .in2(threshold_n), .ci(1'b0), .co(above), .sum(diff));

    DffSyncRst #(.WIDTH(1), .RST_VAL(1'b0)) u_dff_sync_rst_eip(
        .clk, .rst_n, .in(above), .out(eip));
    DffSyncRst #(.WIDTH(IDW)) u_dff_sync_rst_claim_id(
        .clk, .rst_n, .in(best_id), .out(claim_id));

    // A notification has a source to claim.
    `DC_ASSERT(a_eip_has_id, !eip || claim_id != '0)

endmodule
