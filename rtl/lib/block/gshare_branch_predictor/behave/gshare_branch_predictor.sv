/* GShare branch predictor: predicts whether a conditional branch is taken, from a table of
 * 2-bit saturating counters indexed by pc XOR global history.
 *
 * The global history holds the outcomes of the last INDEX_WIDTH conditional branches
 * (1: taken), the newest in bit 0. Predict: predict_pc of the instruction requested in
 * this cycle gives index = predict_pc ^ history; one clock later predict_taken,
 * predict_index and predict_counter come out (a 1-clock read, like an instruction memory)
 * and hold while predict_en=0. The user carries index and counter with the branch to its
 * update: update_en with the outcome writes the counter one step towards it
 * (BranchCounterPkg::update) at update_index, and shifts the outcome into the
 * history. A read and a write of the same entry in one cycle read the old counter.
 * The table has no reset (in hardware it is a memory): it starts with garbage, which
 * only costs mispredictions; this model starts with every counter strongly not taken.
 * The history resets to 0. INDEX_WIDTH is at least 2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module GshareBranchPredictor import BranchCounterPkg::*; #(
    parameter INDEX_WIDTH = 8               // table of 1 << INDEX_WIDTH counters
)(
    input  wire                    clk,
    input  wire                    rst_n,              // synchronous reset, active low

    // Predict
    input  wire                    predict_en,
    input  wire [INDEX_WIDTH-1:0]  predict_pc,         // low bits of the pc as word address
    output wire                    predict_taken,
    output logic [INDEX_WIDTH-1:0] predict_index,      // carried with the branch to its update
    output counter_e               predict_counter,    // carried too: the update needs no read

    // Update: a conditional branch resolved; index and counter of its prediction.
    input  wire                    update_en,
    input  wire [INDEX_WIDTH-1:0]  update_index,
    input  counter_e               update_counter,
    input  wire                    update_taken
);
    logic [INDEX_WIDTH-1:0] history;        // outcomes of the last branches, newest in bit 0
    logic [INDEX_WIDTH-1:0] index;          // entry of the prediction in this cycle
    counter_e               pht [1 << INDEX_WIDTH];     // pattern history table

    assign index = predict_pc ^ history;

    always_ff @(posedge clk)
        if (predict_en) begin
            predict_index   <= index;
            predict_counter <= pht[index];
        end

    assign predict_taken = counter_taken(predict_counter);

    always_ff @(posedge clk)
        if (update_en)
            pht[update_index] <= update(update_counter, update_taken);

    always_ff @(posedge clk)
        if (!rst_n)         history <= '0;
        else if (update_en) history <= {history[INDEX_WIDTH-2:0], update_taken};

    initial
        for (int i = 0; i < (1 << INDEX_WIDTH); i++)
            pht[i] = CNT_STRONG_NOT_TAKEN;

endmodule
