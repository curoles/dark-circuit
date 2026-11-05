/* Mig3 atomics: the reservation of LR.W and SC.W (Zalrsc), in EX. Everything of LR/SC
 * that is not a load or a store is here (kb rtl/design/mig3/lr_sc).
 *
 * LR.W is a load and SC.W a store for the rest of the core (decode: mem.read, mem.write;
 * the address is rs1, imm is 0); dec.atomic tells this part which one it is. The
 * reservation is one word: valid and its word address.
 * - An LR that completes (done) reserves its word.
 * - An SC succeeds when the reservation is valid and its word is the SC's (rs1_data, from
 *   the ID/EX register: the compare does not wait for the address adder). A failing SC
 *   cancels its store (Mig3Lsu sends no request, the retire trace no write); rd_data is
 *   0 for success, 1 for failure (rd_src RD_ATOMIC). rd_data goes to MEM/WB only, not into
 *   EX's forwarding: the compare stays off that path (it made it 0.5 ns longer), and
 *   Mig3Control holds an instruction that reads it, as after a load.
 * - The reservation ends when an SC completes (succeeding or not), on a trap and when MRET
 *   completes. A store of this hart to the reserved word keeps it (the spec allows it).
 * Only an instruction that completes or traps in EX changes the reservation: one on a
 * wrong path never gets that far, one that waits in EX (a load in MEM/WB waits, the
 * D-cache does not take the request) decides on the same reservation every cycle. A
 * misaligned LR or SC traps (Mig3Lsu, Mig3Control): it reserves nothing, and its trap
 * ends the reservation.
 *
 *   dec.atomic, rs1_data --> +----------------------+ --> cancel  (Mig3Lsu: no store)
 *   done, trap, MRET ------> | reservation: valid,  | --> rd_data (SC: 0 ok, 1 fail)
 *                            | word address         |
 *                            +----------------------+
 *
 * Mig3Core instantiates it in EX, for the instruction in EX, next to Mig3Lsu.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig3Atomic import Mig3Pkg::*; (
    input  wire      clk,
    input  wire      rst_n,         // synchronous reset, active low
    input  wire      valid,         // instruction in EX is valid
    input  wire      done,          // it completes in this cycle
    // Of dec only atomic and sys.mret are used, of rs1_data the word address, of trap valid.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t dec,
    input  word_t    rs1_data,      // address of LR and SC (imm is 0)
    input  trap_t    trap,          // it traps in this cycle
    /* verilator lint_on UNUSEDSIGNAL */
    output wire      cancel,        // SC fails: its store is not done
    output word_t    rd_data        // SC: 0 when it succeeds, 1 when it fails
);
    logic   resv_valid;     // a word is reserved
    daddr_t resv_addr;      // its word address
    daddr_t addr;           // the word of the LR or SC in EX
    logic   sc_ok;          // the SC in EX succeeds
    logic   resv_take;      // an LR completes: it reserves its word
    logic   resv_end;       // the reservation ends: an SC completes, a trap, MRET completes
                            // (later also: a snoop of the reserved line)

    assign addr  = rs1_data[WIDTH-1:DADDR_START];
    assign sc_ok = resv_valid && resv_addr == addr;

    assign cancel  = valid && dec.atomic.sc && !sc_ok;
    assign rd_data = word_t'(!sc_ok);

    // Every reason the reservation ends, in one place.
    assign resv_take = done && dec.atomic.lr;
    assign resv_end  = trap.valid || (done && (dec.atomic.sc || dec.sys.mret));

    // Clear first, set last: a trapping instruction does not complete, so the two never
    // meet; MRET and an SC end the reservation, an LR takes it.
    always_ff @(posedge clk)
        if (!rst_n || resv_end)
            resv_valid <= 1'b0;
        else if (resv_take)
            resv_valid <= 1'b1;

    // No reset: the address means nothing while resv_valid is 0.
    always_ff @(posedge clk)
        if (resv_take)
            resv_addr <= addr;

    // An instruction that completes does not trap.
    `DC_ASSERT(a_done_no_trap, !(done && trap.valid))
    // An LR that completes reserves its word.
    `DC_ASSERT_NEXT(a_lr_reserves, resv_take, resv_valid && resv_addr == $past(addr))
    // After an SC, a trap or MRET nothing is reserved.
    `DC_ASSERT_NEXT(a_reservation_ends, resv_end, !resv_valid)

endmodule
