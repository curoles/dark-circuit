/* PLIC interrupt gateway: one interrupt source turned into requests to the PLIC core, one at
 * a time; made of parts and gates.
 *
 * Same ports and behavior as the behave version (see there). The request is src itself
 * (level) or the rising edge an EdgeDetector finds in it (edge). Two DffSyncRst hold the
 * pending bit (ip) and active. With c = complete & ~ip (a complete after the claim):
 *
 *   take        = set & (c | ~active)        Ind2 (c | ~active), And2
 *   ip_next     = (ip & ~claim) | take       Ao21
 *   active_next = (active & ~c) | take       Ao21
 *
 * active & ~c is "active and not done" (done = active & c).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module PlicGateway #(
    parameter EDGE_TRIGGERED = 0    // 1: a rising edge of src is a request, 0: src at 1
)(
    input  wire clk,
    input  wire rst_n,              // synchronous reset, active low
    input  wire src,                // the device's interrupt
    input  wire claim,              // a target claims this source (pulse)
    input  wire complete,           // its handler completes (pulse)
    output wire ip                  // pending in the PLIC core
);
    `DC_STATIC_ASSERT(a_mode, EDGE_TRIGGERED == 0 || EDGE_TRIGGERED == 1)

    wire pending;       // ip
    wire pending_n;
    wire active;        // pending or in service: no other request
    wire set;           // the device requests now
    wire c;             // complete after the claim
    wire c_n;
    wire claim_n;
    wire free;          // c | ~active: a request may go to the PLIC core
    wire take;          // a request goes to the PLIC core now
    wire pending_d;
    wire active_d;

    if (EDGE_TRIGGERED) begin: g_edge
        EdgeDetector #(.EDGE(1), .RST_VAL(1'b0)) u_edge_detector(
            .clk, .rst_n, .in(src), .edge_detected(set));
    end else begin: g_level
        assign set = src;
    end

    // @kb: rtl/lib/block/plic/gateway
    Inv  #(1) u_inv_pending(.in(pending), .out(pending_n));
    And2 #(1) u_and2_c(.in1(complete), .in2(pending_n), .out(c));
    Inv  #(1) u_inv_c(.in(c), .out(c_n));
    Inv  #(1) u_inv_claim(.in(claim), .out(claim_n));
    Ind2 #(1) u_ind2_free(.in1(c), .in2(active), .out(free));
    And2 #(1) u_and2_take(.in1(set), .in2(free), .out(take));
    Ao21 #(1) u_ao21_pending(.in1(pending), .in2(claim_n), .in3(take), .out(pending_d));
    Ao21 #(1) u_ao21_active(.in1(active), .in2(c_n), .in3(take), .out(active_d));

    DffSyncRst #(.WIDTH(1), .RST_VAL(1'b0)) u_dff_sync_rst_pending(
        .clk, .rst_n, .in(pending_d), .out(pending));
    DffSyncRst #(.WIDTH(1), .RST_VAL(1'b0)) u_dff_sync_rst_active(
        .clk, .rst_n, .in(active_d), .out(active));

    assign ip = pending;

    // A pending source is active.
    `DC_ASSERT(a_pending_active, !pending || active)

endmodule
