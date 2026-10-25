/* Counters of GshareBranchPredictor, shared by its versions: 2-bit saturating counters
 * of the pattern history table.
 *
 * A counter says how sure the predictor is that a branch is taken. It moves one step
 * towards the outcome of every resolved branch and saturates at both ends, so a single
 * surprise does not flip a strong prediction (a loop branch that falls through once
 * stays predicted taken). The prediction is taken in the two taken states.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package GshareBranchPredictorPkg;

    // 2-bit saturating counter, from strongly not taken to strongly taken.
    typedef enum logic [1:0] {
        CNT_STRONG_NOT_TAKEN,
        CNT_WEAK_NOT_TAKEN,
        CNT_WEAK_TAKEN,
        CNT_STRONG_TAKEN
    } counter_e;

    // Prediction of a counter: taken in the two taken states.
    function automatic logic predict_taken(input counter_e counter);
        return counter == CNT_WEAK_TAKEN || counter == CNT_STRONG_TAKEN;
    endfunction

    // Counter after a branch resolved: one step towards the outcome, saturating at both ends.
    function automatic counter_e update(input counter_e counter, input logic taken);
        if (taken)
            case (counter)
                CNT_STRONG_NOT_TAKEN: return CNT_WEAK_NOT_TAKEN;
                CNT_WEAK_NOT_TAKEN:   return CNT_WEAK_TAKEN;
                CNT_WEAK_TAKEN:       return CNT_STRONG_TAKEN;
                CNT_STRONG_TAKEN:     return CNT_STRONG_TAKEN;
            endcase
        else
            case (counter)
                CNT_STRONG_NOT_TAKEN: return CNT_STRONG_NOT_TAKEN;
                CNT_WEAK_NOT_TAKEN:   return CNT_STRONG_NOT_TAKEN;
                CNT_WEAK_TAKEN:       return CNT_WEAK_NOT_TAKEN;
                CNT_STRONG_TAKEN:     return CNT_WEAK_TAKEN;
            endcase
    endfunction

endpackage
