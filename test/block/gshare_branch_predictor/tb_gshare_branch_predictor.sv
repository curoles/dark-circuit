/* Test of GshareBranchPredictor, both versions (the same testbench).
 *
 * The table has no reset (the struct table starts unknown): first the test writes every
 * entry strongly not taken, with updates during reset, which keep the history 0.
 *
 * 1. Random: random predictions (pc, enable) and updates of earlier predictions with
 *    random outcomes, the way a pipeline uses the block: index and counter of a
 *    prediction come back with its update, up to 3 predictions are in flight. A model
 *    of its own (table, history and counters as integers, the counter as an up/down
 *    count that saturates at 0 and 3) checks every output after every clock, also the
 *    hold while predict_en=0 and a read of the entry that is written in the same cycle.
 *    One reset in the middle clears the history and keeps the table.
 * 2. Loop: one branch taken INDEX_WIDTH-1 times, then not taken, repeated. With
 *    INDEX_WIDTH bits of history the predictor knows where in the loop it is: after 4
 *    rounds of learning it predicts every outcome right.
 * Verilator runs INDEX_WIDTH 4 (many entries shared) and 8 with 20000 random clocks; Icarus,
 * slow on the gates of the struct table, INDEX_WIDTH 4 with 2000. Stops at the first
 * mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbGshareCheck import BranchCounterPkg::*; #(
    parameter INDEX_WIDTH = 4
)(
    input  wire  clk,
    output logic done
);
    localparam ENTRIES  = 1 << INDEX_WIDTH;
`ifdef VERILATOR
    localparam N_RANDOM = 20000;    // clocks of the random test
`else
    localparam N_RANDOM = 2000;
`endif
    localparam DEPTH    = 3;        // predictions in flight at most

    logic                   rst_n;
    logic                   predict_en;
    logic [INDEX_WIDTH-1:0] predict_pc;
    wire                    predict_taken;
    logic [INDEX_WIDTH-1:0] predict_index;
    counter_e               predict_counter;
    logic                   update_en;
    logic [INDEX_WIDTH-1:0] update_index;
    counter_e               update_counter;
    logic                   update_taken;

    // Model.
    integer                 m_pht [ENTRIES];    // counters 0..3
    integer                 m_history;
    integer                 m_index;            // outputs of the last prediction
    integer                 m_counter;

    // Predictions in flight: index and counter, oldest at head.
    integer                 fl_index [DEPTH];
    integer                 fl_counter [DEPTH];
    integer                 fl_n;

    integer                 seed;
    integer                 wrong;

    GshareBranchPredictor #(.INDEX_WIDTH(INDEX_WIDTH)) u_gshare_branch_predictor(
        .clk, .rst_n, .predict_en, .predict_pc, .predict_taken, .predict_index,
        .predict_counter, .update_en, .update_index, .update_counter, .update_taken);

    // Model of one rising edge with the inputs of this cycle: the prediction reads the
    // table before the update of the same edge writes it.
    task automatic model_edge;
        integer c;
        if (predict_en) begin
            m_index   = (32'(predict_pc) ^ m_history) % ENTRIES;
            m_counter = m_pht[m_index];
        end
        if (!rst_n)
            m_history = 0;
        if (update_en) begin
            c = 32'(update_counter);
            if (update_taken)
                c = (c == 3) ? 3 : c + 1;
            else
                c = (c == 0) ? 0 : c - 1;
            m_pht[update_index] = c;
            if (rst_n)
                m_history = ((m_history << 1) | 32'(update_taken)) % ENTRIES;
        end
    endtask

    // After a rising edge: the outputs are those of the model.
    task automatic check(input string what);
        if (predict_index !== m_index[INDEX_WIDTH-1:0] || predict_counter !== m_counter[1:0] ||
            predict_taken !== (m_counter >= 2))
            $fatal(1, "Gshare %0d %s: index %h counter %0d taken %b, expected %h %0d %b",
                   INDEX_WIDTH, what, predict_index, predict_counter, predict_taken,
                   m_index, m_counter, m_counter >= 2);
    endtask

    // One clock: inputs set at the falling edge, the model takes the rising edge.
    task automatic clock(input string what);
        model_edge();
        @(negedge clk);
        check(what);
    endtask

    task automatic idle;
        predict_en = 1'b0;
        update_en  = 1'b0;
    endtask

    // 1. Random predictions and updates of predictions in flight.
    task automatic random_test;
        // Bits of r: 0 predict, 1 update, 2 outcome, 4 and up the pc; the rest unused.
        /* verilator lint_off UNUSEDSIGNAL */
        integer r;
        /* verilator lint_on UNUSEDSIGNAL */
        logic   pushed;
        fl_n = 0;
        for (int k = 0; k < N_RANDOM; k++) begin
            r          = $random(seed);
            rst_n      = (k != N_RANDOM / 2);
            predict_en = r[0] && fl_n < DEPTH;
            predict_pc = r[INDEX_WIDTH+3:4];
            update_en  = r[1] && fl_n > 0;
            if (update_en) begin
                update_index   = fl_index[0][INDEX_WIDTH-1:0];
                update_counter = counter_e'(fl_counter[0][1:0]);
                update_taken   = r[2];
                for (int i = 1; i < DEPTH; i++) begin
                    fl_index[i-1]   = fl_index[i];
                    fl_counter[i-1] = fl_counter[i];
                end
                fl_n = fl_n - 1;
            end
            pushed = predict_en;
            clock("random");
            if (pushed) begin
                fl_index[fl_n]   = 32'(predict_index);
                fl_counter[fl_n] = 32'(predict_counter);
                fl_n = fl_n + 1;
            end
        end
        rst_n = 1'b1;
        idle();
    endtask

    // 2. Loop branch at one pc: predict, then update with the outcome, 16 rounds.
    task automatic loop_test;
        logic taken;
        wrong = 0;
        for (int k = 0; k < 16 * INDEX_WIDTH; k++) begin
            taken      = (k % INDEX_WIDTH) != INDEX_WIDTH - 1;
            predict_en = 1'b1;
            predict_pc = INDEX_WIDTH'(42);
            update_en  = 1'b0;
            clock("loop predict");
            if (k >= 4 * INDEX_WIDTH && predict_taken !== taken)
                wrong = wrong + 1;
            predict_en     = 1'b0;
            update_en      = 1'b1;
            update_index   = predict_index;
            update_counter = predict_counter;
            update_taken   = taken;
            clock("loop update");
        end
        idle();
        if (wrong != 0)
            $fatal(1, "Gshare %0d loop: %0d wrong predictions after learning", INDEX_WIDTH, wrong);
    endtask

    initial begin
        done = 1'b0;
        seed = INDEX_WIDTH;
        for (int i = 0; i < ENTRIES; i++)
            m_pht[i] = 0;               // written strongly not taken below
        m_history = 0;
        m_index   = 0;
        m_counter = 0;
        rst_n = 1'b0;
        idle();
        predict_pc     = '0;
        update_index   = '0;
        update_counter = CNT_STRONG_NOT_TAKEN;
        update_taken   = 1'b0;
        // Reset, the table written, and a first prediction so that the outputs are defined.
        @(negedge clk);
        model_edge();
        @(negedge clk);
        update_en = 1'b1;
        for (int i = 0; i < ENTRIES; i++) begin
            update_index = INDEX_WIDTH'(i);
            model_edge();
            @(negedge clk);
        end
        update_en  = 1'b0;
        rst_n      = 1'b1;
        predict_en = 1'b1;
        clock("first prediction");
        idle();
        random_test();
        loop_test();
        done = 1'b1;
    end
endmodule

module TbGshareBranchPredictor;
`ifdef VERILATOR
    localparam bit WIDE = 1'b1;     // also INDEX_WIDTH 8
`else
    localparam bit WIDE = 1'b0;
`endif
    wire clk;
    wire done4;
    wire done8;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbGshareCheck #(.INDEX_WIDTH(4)) u_check_4(.clk, .done(done4));
    if (WIDE) begin: g_wide
        TbGshareCheck #(.INDEX_WIDTH(8)) u_check_8(.clk, .done(done8));
    end else begin: g_narrow
        assign done8 = 1'b1;
    end

    initial begin
        wait (done4 && done8);
        $display("PASS");
        $finish;
    end
endmodule
