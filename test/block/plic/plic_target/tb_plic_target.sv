/* Test of PlicTarget, behave or struct version.
 *
 * Model, unlike both versions: from the highest priority down to 1, the lowest ID of an
 * eligible source (pending, enabled) of that priority; the first found is the claim ID (0
 * if none), and eip is its priority above the threshold. The inputs change after a rising
 * edge; one clock later (the outputs are registered) eip and claim_id are compared with the
 * model of those inputs. Every configuration gets directed cases, then random inputs (few or
 * many sources pending, enabled, priorities and threshold at random): 3000 cycles on
 * Verilator, 300 on Icarus. Every case must happen (checks named cover): no source
 * eligible, a pending and enabled source of priority 0 passed over, a tie of the highest
 * priority, a winner not above the threshold (claim ID, no eip), eip. Checks named model
 * and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbPlicTargetCheck #(
    parameter N_SOURCES  = 7,
    parameter PRIO_WIDTH = 3
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
`ifdef VERILATOR
    localparam N_RANDOM = 3000;
`else
    localparam N_RANDOM = 300;
`endif
    localparam IDW    = $clog2(N_SOURCES + 1);
    localparam MAX_PR = (1 << PRIO_WIDTH) - 1;

    typedef logic [PRIO_WIDTH-1:0] prio_t;

    logic [N_SOURCES:0]               ip;
    logic [N_SOURCES:0]               ie;
    logic [N_SOURCES:0][PRIO_WIDTH-1:0] prio;
    prio_t                            threshold;
    wire                              eip;
    wire  [IDW-1:0]                   claim_id;
    logic                             exp_eip;    // the model, for the inputs of the cycle
    int                               exp_id;
    integer                           seed;
    logic [N_SOURCES:0]               mask;
    // Coverage.
    logic seen_none, seen_prio0, seen_tie, seen_below, seen_eip;

    PlicTarget #(.N_SOURCES(N_SOURCES), .PRIO_WIDTH(PRIO_WIDTH)) u_plic_target(
        .clk, .rst_n, .ip, .ie, .prio, .threshold, .eip, .claim_id);

    // The model for the inputs now; also counts the cases.
    task automatic model();
        int found;
        int ties;
        found = 0;
        ties  = 0;
        for (int p = MAX_PR; p >= 1 && found == 0; p--)
            for (int k = N_SOURCES; k >= 1; k--)
                if (ip[k] && ie[k] && int'(prio[k]) == p) begin
                    found = k;
                    ties++;
                end
        exp_id  = found;
        exp_eip = found != 0 && prio[found] > threshold;
        if (found == 0)
            seen_none = 1'b1;
        if (ties > 1)
            seen_tie = 1'b1;
        if (found != 0 && !exp_eip)
            seen_below = 1'b1;
        if (exp_eip)
            seen_eip = 1'b1;
        for (int k = 1; k <= N_SOURCES; k++)
            if (ip[k] && ie[k] && prio[k] == '0)
                seen_prio0 = 1'b1;
    endtask

    // One cycle: the model of the inputs set now; the outputs after the rising edge.
    task automatic cycle();
        model();
        @(posedge clk);
        #1;
        if (eip !== exp_eip || int'(claim_id) !== exp_id)
            `DC_TEST_FAIL(model, $sformatf(
                "PlicTarget N=%0d PRIO_WIDTH=%0d: eip %b claim_id %0d, expected %b %0d",
                N_SOURCES, PRIO_WIDTH, eip, claim_id, exp_eip, exp_id))
    endtask

    function automatic prio_t random_prio();
        return prio_t'($random(seed));
    endfunction

    initial begin
        done = 1'b0;
        {seen_none, seen_prio0, seen_tie, seen_below, seen_eip} = '0;
        seed = N_SOURCES * 10 + PRIO_WIDTH;
        {ip, ie, prio, threshold} = '0;
        @(posedge rst_n);
        // Nothing pending.
        cycle();
        // Every source pending and enabled, priority 0: none eligible.
        ip = '1;
        ie = '1;
        cycle();
        // The highest priority at the last source, also at the first: the first wins.
        for (int k = 1; k <= N_SOURCES; k++)
            prio[k] = 1;
        prio[N_SOURCES] = MAX_PR;
        prio[1]         = MAX_PR;
        cycle();
        // The threshold at the winner's priority: a claim ID, no eip; one below: eip.
        threshold = MAX_PR;
        cycle();
        threshold = MAX_PR - 1;
        cycle();
        // The winner disabled: the next one wins.
        ie[1]          = 1'b0;
        ie[N_SOURCES]  = 1'b0;
        threshold      = '0;
        cycle();
        for (int i = 0; i < N_RANDOM; i++) begin
            for (int k = 1; k <= N_SOURCES; k++)
                prio[k] = random_prio();
            // Pending: about a half or a quarter of the sources; enabled: a half or all.
            mask      = (i % 3 == 0) ? '1 : (N_SOURCES + 1)'($random(seed));
            ip        = (N_SOURCES + 1)'($random(seed)) & mask;
            ie        = (N_SOURCES + 1)'($random(seed)) | ((i % 4 == 0) ? '1 : '0);
            threshold = (i % 5 == 0) ? '0 : random_prio();
            cycle();
        end
        cycle();
        if (!seen_none || !seen_prio0 || (N_SOURCES > 1 && !seen_tie) || !seen_below || !seen_eip)
            `DC_TEST_FAIL(cover, $sformatf(
                "PlicTarget N=%0d PRIO_WIDTH=%0d: none %b prio0 %b tie %b below %b eip %b",
                N_SOURCES, PRIO_WIDTH, seen_none, seen_prio0, seen_tie, seen_below, seen_eip))
        done = 1'b1;
    end
endmodule

module TbPlicTarget;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_1_1, done_3_2, done_7_3, done_31_3, done_32_4;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbPlicTargetCheck #(.N_SOURCES(1),  .PRIO_WIDTH(1)) u_check_1_1(.clk, .rst_n, .done(done_1_1));
    TbPlicTargetCheck #(.N_SOURCES(3),  .PRIO_WIDTH(2)) u_check_3_2(.clk, .rst_n, .done(done_3_2));
    TbPlicTargetCheck #(.N_SOURCES(7),  .PRIO_WIDTH(3)) u_check_7_3(.clk, .rst_n, .done(done_7_3));
    TbPlicTargetCheck #(.N_SOURCES(31), .PRIO_WIDTH(3)) u_check_31_3(
        .clk, .rst_n, .done(done_31_3));
    TbPlicTargetCheck #(.N_SOURCES(32), .PRIO_WIDTH(4)) u_check_32_4(
        .clk, .rst_n, .done(done_32_4));

    initial begin
        wait (done_1_1 && done_3_2 && done_7_3 && done_31_3 && done_32_4);
        $display("PASS");
        $finish;
    end
endmodule
