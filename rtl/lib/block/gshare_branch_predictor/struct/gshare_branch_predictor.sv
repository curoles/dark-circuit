/* GShare branch predictor, made of blocks and gates: predicts whether a conditional branch
 * is taken, from a table of 2-bit saturating counters indexed by pc XOR global history.
 *
 * Same ports and behavior as the behave version (see there), but the table is Sram1R1W
 * and starts unknown: the user writes every entry (an update of each index) before it
 * trusts the predictions, or accepts unknown predictions until the entries are written.
 * The history resets to 0. INDEX_WIDTH is at least 2.
 *
 * Index: Xor2 of predict_pc and the history. The table reads at predict_en into its
 * data_out (predict_counter), which holds while predict_en=0; predict_index is Mux2 and
 * Dff with the same hold. predict_taken is the high bit of the counter (the two taken
 * states of counter_e). Update: the counter one step towards the outcome t, saturating
 * (GshareBranchPredictorPkg::update), bit by bit, with c1 c0 the bits of update_counter:
 *   new c1 = Maj3(c1,  c0, t): taken c1 | c0,  not taken c1 & c0
 *   new c0 = Maj3(c1, ~c0, t): taken c1 | ~c0, not taken c1 & ~c0
 * The history is DffSyncRstEn: update_en shifts the outcome into bit 0.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module GshareBranchPredictor import GshareBranchPredictorPkg::*; #(
    parameter INDEX_WIDTH = 8               // table of 1 << INDEX_WIDTH counters
)(
    input  wire                    clk,
    input  wire                    rst_n,              // synchronous reset, active low

    // Predict
    input  wire                    predict_en,
    input  wire [INDEX_WIDTH-1:0]  predict_pc,         // low bits of the pc as word address
    output wire                    predict_taken,
    output wire [INDEX_WIDTH-1:0]  predict_index,      // carried with the branch to its update
    output counter_e               predict_counter,    // carried too: the update needs no read

    // Update: a conditional branch resolved; index and counter of its prediction.
    input  wire                    update_en,
    input  wire [INDEX_WIDTH-1:0]  update_index,
    input  counter_e               update_counter,
    input  wire                    update_taken
);
    wire [INDEX_WIDTH-1:0] history;         // outcomes of the last branches, newest in bit 0
    wire [INDEX_WIDTH-1:0] history_next;
    wire [INDEX_WIDTH-1:0] index;           // entry of the prediction in this cycle
    wire [INDEX_WIDTH-1:0] index_next;
    wire [1:0]             counter;         // predict_counter as bits
    wire [1:0]             counter_new;     // update_counter one step towards update_taken
    wire                   c0_n;

    Xor2 #(INDEX_WIDTH) u_xor2(.in1(predict_pc), .in2(history), .out(index));

    // Pattern history table.
    Sram1R1W #(.ADDR_WIDTH(INDEX_WIDTH), .DATA_WIDTH(2)) u_sram_1r1w(
        .clk(clk),
        .rd_en(predict_en), .rd_addr(index), .data_out(counter),
        .wr_en(update_en), .wr_addr(update_index), .data_in(counter_new));

    assign predict_counter = counter_e'(counter);
    assign predict_taken   = counter[1];

    // predict_index holds while predict_en is 0, like the table output.
    Mux2 #(INDEX_WIDTH) u_mux2(.in0(predict_index), .in1(index), .sel(predict_en),
                               .out(index_next));
    Dff  #(INDEX_WIDTH) u_dff (.clk(clk), .in(index_next), .out(predict_index));

    // Saturating step of the counter.
    Inv  #(1) u_inv   (.in(update_counter[0]), .out(c0_n));
    Maj3 #(1) u_maj3_1(.in1(update_counter[1]), .in2(update_counter[0]), .in3(update_taken),
                       .out(counter_new[1]));
    Maj3 #(1) u_maj3_0(.in1(update_counter[1]), .in2(c0_n), .in3(update_taken),
                       .out(counter_new[0]));

    // Global history.
    assign history_next = {history[INDEX_WIDTH-2:0], update_taken};

    DffSyncRstEn #(.WIDTH(INDEX_WIDTH)) u_dff_sync_rst_en(
        .clk(clk), .rst_n(rst_n), .en(update_en), .in(history_next), .out(history));

endmodule
