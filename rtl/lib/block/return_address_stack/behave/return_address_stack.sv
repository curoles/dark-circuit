/* Return-address stack, behavioral: predicts where a return goes.
 *
 * A call pushes its return address (push, push_addr); a return pops it (pop), and
 * top_addr, the newest address, is its prediction: a return goes back to the last call that
 * has not returned yet. push and pop in the same cycle replace the top (a return that is
 * also a call: the coroutine swap, JALR x5, 0(x1) in RISC-V). When more calls are nested
 * than the stack holds, a push overwrites the oldest address: the newest ones matter for the
 * next returns. top_addr is a prediction also when the stack is empty (a stale address): the
 * user checks every prediction anyway. Stack with OVERWRITE=1; rst_n=0 empties it.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module ReturnAddressStack #(
    parameter ADDR_WIDTH = 3,                   // 1 << ADDR_WIDTH addresses
    parameter DATA_WIDTH = 30                   // a return address
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  wire                  push,          // a call
    input  wire [DATA_WIDTH-1:0] push_addr,     // its return address
    input  wire                  pop,           // a return
    output wire [DATA_WIDTH-1:0] top_addr       // where a return now goes, predicted
);
    // A prediction is checked by the user, so emptiness does not matter here.
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  empty;
    wire                  full;
    wire [ADDR_WIDTH:0]   count;
    /* verilator lint_on UNUSEDSIGNAL */

    Stack #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .OVERWRITE(1)) u_stack(
        .clk, .rst_n, .push, .data_in(push_addr), .pop, .data_out(top_addr), .empty, .full,
        .count);

endmodule
