/* PLIC interrupt gateway: one interrupt source turned into requests to the PLIC core, one at
 * a time (RISC-V PLIC spec, "Interrupt Gateways").
 *
 * src is the device's interrupt, synchronous to clk (a source on another clock is
 * synchronized by the platform before it, not here). EDGE_TRIGGERED, fixed by the platform:
 * 0, the device holds src at 1 while it wants service (level); 1, the device signals an event
 * with a rising edge of src. A request (set) is src at 1, or a rising edge of src.
 *
 * ip, the pending bit of the source in the PLIC core, rises with a request and falls when a
 * target claims the source (claim). From the request until the handler completes (complete)
 * the source is active, and the gateway forwards no other request:
 *
 *   idle --request--> pending (ip=1) --claim--> in service --complete--> idle
 *   |<------------------------------- active ------------------------------->|
 *
 * - A level source still at 1 after complete makes the next request at once; one that falls
 *   to 0 before the claim stays pending (the spec: the handler finds the device needs nothing).
 * - An edge while the source is active is ignored: the device must keep its own status of
 *   what happened, which the handler reads (kb rtl/lib/block/plic/gateway). A request in the
 *   very cycle of complete is taken.
 * - A complete while the source is pending (before its claim) is ignored, as a claim while
 *   it is not pending.
 * claim and complete are one-cycle pulses from the PLIC core (its claim/complete register).
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

    logic pending;      // ip
    logic active;       // pending or in service: no other request
    logic set;          // the device requests now
    logic done;         // the handler completes now
    logic take;         // a request goes to the PLIC core now

    if (EDGE_TRIGGERED) begin: g_edge
        logic src_q;    // src one clock earlier
        always_ff @(posedge clk)
            if (!rst_n) src_q <= 1'b0;
            else        src_q <= src;
        assign set = src && !src_q;
    end else begin: g_level
        assign set = src;
    end

    // @kb: rtl/lib/block/plic/gateway
    assign done = active && complete && !pending;
    assign take = set && (!active || done);

    always_ff @(posedge clk)
        if (!rst_n) begin
            pending <= 1'b0;
            active  <= 1'b0;
        end else begin
            pending <= (pending && !claim) || take;
            active  <= take || (active && !done);
        end

    assign ip = pending;

    // A pending source is active.
    `DC_ASSERT(a_pending_active, !pending || active)

endmodule
