/* Interrupt source of Mig3 for testbenches: a device, its interrupt line (meip here) is
 * source 1 of the PLIC of Mig3Cpu.
 *
 * With enable (+irq_random=<seed>) meip rises max_gap clocks after reset (+irq_max_gap=<n>,
 * default 200), later after a random gap of 1 to max_gap clocks, and stays 1 until the
 * program claims the interrupt: a
 * store to the word claim_addr retires (the symbol irq_claim of the program, as a handler
 * claims at the claim register of a PLIC). Then it falls and the next gap starts. A handler
 * that returns without claiming gets the interrupt again: meip is a level. Without enable
 * meip stays 0. The gaps come from a xorshift of the seed, the same in every simulator. The
 * trace gets a line when meip rises and when it is claimed.
 *
 * TbMig3 instantiates it.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig3Irq import Mig3Pkg::*; (
    input  wire         clk,
    input  wire         rst_n,          // synchronous reset, active low
    input  wire         enable,         // +irq_random given
    input  int unsigned seed,           // +irq_random=<seed>
    input  int unsigned max_gap,        // the longest gap before meip rises, in clocks
    input  word_t       claim_addr,     // byte address of the claim word (irq_claim)
    // Only valid, trap, mem_addr and mem_wmask are used: a store to the claim word.
    /* verilator lint_off UNUSEDSIGNAL */
    input  retire_t     retire,
    /* verilator lint_on UNUSEDSIGNAL */
    input  integer      cycle,          // cycle number of the trace (TbMig3)
    input  integer      trace_fd,       // trace file of TbMig3, 0: no trace
    output logic        meip            // machine external interrupt pending
);
    int unsigned rnd;       // xorshift state
    int unsigned rnd_next;  // the next one
    int unsigned gap;       // clocks left before meip rises
    logic        claimed;   // a store to the claim word retires

    // Next random number: xorshift32 (Marsaglia).
    function automatic int unsigned xorshift(input int unsigned x);
        x = x ^ (x << 13);
        x = x ^ (x >> 17);
        x = x ^ (x << 5);
        return x;
    endfunction

    assign rnd_next = xorshift(rnd);
    // irq_claim is a word: its address is word aligned, as mem_addr.
    assign claimed  = retire.valid && !retire.trap && retire.mem_wmask != '0 &&
                      retire.mem_addr == claim_addr;

    always @(posedge clk)
        if (!rst_n) begin
            meip <= 1'b0;
            rnd  <= (seed == 0) ? 32'h1 : seed;     // xorshift needs a state that is not 0
            gap  <= max_gap;
        end else if (enable) begin
            if (meip && claimed) begin
                meip <= 1'b0;
                rnd  <= rnd_next;
                gap  <= 1 + rnd_next % max_gap;
                if (trace_fd != 0)
                    $fdisplay(trace_fd, "%8d irq claimed", cycle);
            end else if (!meip) begin
                if (gap <= 1) begin
                    meip <= 1'b1;
                    if (trace_fd != 0)
                        $fdisplay(trace_fd, "%8d irq meip", cycle);
                end else
                    gap <= gap - 1;
            end
        end

endmodule
