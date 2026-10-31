/* NoC virtual channel, the output end: one VC of the next router's input, as the sender sees
 * it; behavioral.
 *
 * A credit count, BUF_DEPTH after reset (the receiver's buffer is empty): a flit sent takes
 * one, a credit coming back (the receiver sent a flit of this VC on) returns one; a flit may go
 * only while the count is above 0 (has_credit). And free: VC allocation gives the VC to a
 * packet (alloc), which holds it until its tail flit is sent.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module NocVirtChOut #(
    parameter BUF_DEPTH = 4                     // the receiver's buffer: credits after reset
)(
    input  wire                   clk,
    input  wire                   rst_n,        // synchronous reset, active low
    input  wire                   alloc,        // VC allocation gives this VC to a packet
    input  wire                   send,         // a flit goes out on this VC
    input  wire                   send_tail,    // ... and it is the packet's tail
    input  wire                   credit,       // a credit for this VC comes back
    output NocPkg::vc_out_state_t state         // free, has_credit: for the allocators
);
    localparam CREDIT_WIDTH = $clog2(BUF_DEPTH + 1);

    `DC_STATIC_ASSERT(a_buf_depth, BUF_DEPTH >= 1)

    logic [CREDIT_WIDTH-1:0] credits;
    logic                    taken;

    always_ff @(posedge clk)
        if (!rst_n) credits <= CREDIT_WIDTH'(BUF_DEPTH);
        else        credits <= credits - CREDIT_WIDTH'(send) + CREDIT_WIDTH'(credit);

    always_ff @(posedge clk)
        if (!rst_n)                 taken <= 1'b0;
        else if (alloc)             taken <= 1'b1;
        else if (send && send_tail) taken <= 1'b0;

    assign state.free       = !taken;
    assign state.has_credit = credits != '0;

    // The protocol around the VC: VC allocation gives only a free VC; switch allocation sends
    // only on a taken VC with a credit; the receiver returns no more credits than it has slots.
    `DC_ASSERT(a_alloc_when_free, !(alloc && taken))
    `DC_ASSERT(a_send_when_taken, !(send && !taken))
    `DC_ASSERT(a_send_with_credit, !(send && credits == '0))
    `DC_ASSERT(a_tail_is_sent, !(send_tail && !send))
    `DC_ASSERT(a_credits_at_most_depth, !(credit && !send && credits == CREDIT_WIDTH'(BUF_DEPTH)))

endmodule
