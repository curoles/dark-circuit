/* Mig2 branch prediction: the guess for the conditional branch in ID, taken or not.
 *
 * Static: backward taken, forward not taken (BTFN). A branch with a negative offset
 * mostly closes a loop and is taken; a forward one mostly skips code that runs rarely.
 * Mig2Control redirects fetch from ID for a branch guessed taken; EX compares the guess
 * with the outcome and corrects it. A version that learns from the outcomes (GShare,
 * rtl/lib/block/gshare_branch_predictor) can replace this one behind the same ports and
 * more ports for the outcomes.
 *
 * Mig2Core instantiates it in ID, for the instruction in ID.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig2BranchPredict import Mig2Pkg::*; (
    // Only br.branch and imm are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t dec,           // instruction in ID taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    output wire      taken          // a conditional branch, guessed taken
);
    assign taken = dec.br.branch && dec.imm[WIDTH-1];

endmodule
