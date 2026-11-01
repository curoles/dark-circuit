/* NoC virtual channel, the output end, made of blocks and gates.
 *
 * Same ports, parameter and behavior as the behave version (see there). It counts the credits
 * in use, not those left: Counter resets to 0 (the receiver's buffer is empty), and has_credit
 * is "in use != BUF_DEPTH". The count moves only when exactly one of a send (up) and a credit
 * (down) happens; both in one clock leave it. A packet takes the VC on alloc and keeps it until
 * its tail goes: taken_next = alloc | (taken & keep), keep = !(send & send_tail), one Ao21.
 *
 *   send ---+--> Xor2 ------------> count_en +---------+
 *   credit -|------^                         | Counter |--> used --> CmpNe --> has_credit
 *           +-----------------------> up_down +---------+        BUF_DEPTH --^
 *
 *   send -----> Nand2 --> keep --> +------+             +------------+
 *   send_tail ----^      taken --> | Ao21 |--> taken -->| DffSyncRst |--+--> Inv --> free
 *   alloc ------------------------>|      |    _next    +------------+  |
 *                          ^       +------+                             |
 *                          +--------------------------------- taken ----+
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

    wire [CREDIT_WIDTH-1:0] used;               // credits in use: flits sent, not returned yet
    wire                    count;              // a send or a credit, not both
    wire                    has_credit;
    wire                    keep;               // the packet's tail does not go now
    wire                    taken_next;
    wire                    taken;
    wire                    free;
    // The count never wraps (0 to BUF_DEPTH): its carry is not used.
    /* verilator lint_off UNUSEDSIGNAL */
    wire                    co;
    /* verilator lint_on UNUSEDSIGNAL */

    Xor2 #(1) u_xor2_count(.in1(send), .in2(credit), .out(count));
    Counter #(.WIDTH(CREDIT_WIDTH)) u_counter_used(
        .clk, .rst_n, .load(1'b0), .in({CREDIT_WIDTH{1'b0}}), .up_down(send), .count_en(count),
        .out(used), .co);
    CmpNe #(CREDIT_WIDTH) u_cmp_ne_has_credit(
        .in1(used), .in2(CREDIT_WIDTH'(BUF_DEPTH)), .ne(has_credit));

    Nand2      #(1) u_nand2_keep(.in1(send), .in2(send_tail), .out(keep));
    Ao21       #(1) u_ao21_taken_next(.in1(taken), .in2(keep), .in3(alloc), .out(taken_next));
    DffSyncRst #(1) u_dff_sync_rst_taken(.clk, .rst_n, .in(taken_next), .out(taken));
    Inv        #(1) u_inv_free(.in(taken), .out(free));

    assign state.free       = free;
    assign state.has_credit = has_credit;

    // The protocol around the VC, as in the behave version.
    `DC_ASSERT(a_alloc_when_free, !(alloc && taken))
    `DC_ASSERT(a_send_when_taken, !(send && !taken))
    `DC_ASSERT(a_send_with_credit, !(send && !has_credit))
    `DC_ASSERT(a_tail_is_sent, !(send_tail && !send))
    `DC_ASSERT(a_credits_at_most_depth, !(credit && !send && used == '0))

endmodule
