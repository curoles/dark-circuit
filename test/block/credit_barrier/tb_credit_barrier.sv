/* Test of CreditBarrier.
 *
 * Random, the way a manager and its participants use the barrier: the manager arms it with
 * random amounts (often 0, small, or near the largest), the participants offer credits of
 * random amounts in random clocks (also while the barrier is not armed or already released:
 * not taken), the manager clears a release after a random wait (and tries to clear and to
 * arm at other times: ignored). A model of its own (armed, released, amount, sum as integers)
 * checks after every clock cfg_ready, credit_ready and barrier_released. In the end the test
 * checks that every case happened: releases by a sum exactly at the amount and beyond it,
 * an amount of 0, credits offered when not taken, arming while armed, clearing while not
 * released, releases after one credit and after several. One reset in the middle disarms.
 * Runs with WIDTH 16 and 4 (the sum near its largest); 20000 clocks on Verilator, 2000 on
 * Icarus. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbCreditBarrierCheck #(
    parameter WIDTH = 16            // up to 30
)(
    input  wire  clk,
    output logic done
);
    localparam integer MAX = (1 << WIDTH) - 1;
`ifdef VERILATOR
    localparam N_CLOCKS = 20000;
`else
    localparam N_CLOCKS = 2000;
`endif

    logic             rst_n;
    logic             cfg_valid;
    logic [WIDTH-1:0] cfg_waiting_amount;
    wire              cfg_ready;
    logic             credit_valid;
    logic [WIDTH-1:0] credit_amount;
    wire              credit_ready;
    wire              barrier_released;
    logic             clear_released;

    // Model.
    logic   m_armed;
    logic   m_released;
    integer m_target;
    integer m_sum;
    integer m_credits;          // credits taken since arming
    integer seed;

    // Cases seen.
    integer n_exact;
    integer n_beyond;
    integer n_zero;
    integer n_not_taken;
    integer n_arm_armed;
    integer n_clear_ignored;
    integer n_one_credit;
    integer n_many_credits;

    CreditBarrier #(.WIDTH(WIDTH)) u_credit_barrier(
        .clk, .rst_n, .cfg_valid, .cfg_waiting_amount, .cfg_ready, .credit_valid,
        .credit_amount, .credit_ready, .barrier_released, .clear_released);

    // After a rising edge: the outputs are those of the model.
    task automatic check;
        if (cfg_ready !== !m_armed || credit_ready !== (m_armed && !m_released) ||
            barrier_released !== m_released)
            $fatal(1, "Barrier %0d: cfg_ready %b credit_ready %b released %b, expected %b %b %b",
                   WIDTH, cfg_ready, credit_ready, barrier_released, !m_armed,
                   m_armed && !m_released, m_released);
    endtask

    // Model of one rising edge with the inputs of this clock.
    task automatic model_edge;
        if (!rst_n) begin
            m_armed    = 1'b0;
            m_released = 1'b0;
            return;
        end
        if (cfg_valid && m_armed)
            n_arm_armed = n_arm_armed + 1;
        if (credit_valid && !(m_armed && !m_released))
            n_not_taken = n_not_taken + 1;
        if (clear_released && !m_released)
            n_clear_ignored = n_clear_ignored + 1;
        if (cfg_valid && !m_armed) begin
            m_armed    = 1'b1;
            m_target   = 32'(cfg_waiting_amount);
            m_sum      = 0;
            m_credits  = 0;
            m_released = m_target == 0;
            if (m_released)
                n_zero = n_zero + 1;
        end else if (credit_valid && m_armed && !m_released) begin
            m_sum     = m_sum + 32'(credit_amount);
            m_credits = m_credits + 1;
            if (m_sum >= m_target) begin
                m_released = 1'b1;
                if (m_sum == m_target)
                    n_exact = n_exact + 1;
                else
                    n_beyond = n_beyond + 1;
                if (m_credits == 1)
                    n_one_credit = n_one_credit + 1;
                else
                    n_many_credits = n_many_credits + 1;
            end
        end else if (m_released && clear_released) begin
            m_armed    = 1'b0;
            m_released = 1'b0;
        end
    endtask

    // A random amount: 0, small, near the largest, or any.
    function automatic logic [WIDTH-1:0] amount(input integer r);
        case (r % 4)
            0:       return '0;
            1:       return WIDTH'(1 + (r / 4) % 4);
            2:       return WIDTH'(MAX - (r / 4) % 4);
            default: return WIDTH'(r / 4);
        endcase
    endfunction

    task automatic random_test;
        // Bits of r: 0..1 arm, 2..3 credit, 4..5 clear, 8 and up the amounts; the rest unused.
        /* verilator lint_off UNUSEDSIGNAL */
        integer r;
        /* verilator lint_on UNUSEDSIGNAL */
        for (int k = 0; k < N_CLOCKS; k++) begin
            r                  = $random(seed);
            rst_n              = (k != N_CLOCKS / 2);
            cfg_valid          = r[1:0] == 2'b00;
            cfg_waiting_amount = amount({8'd0, r[31:8]});
            credit_valid       = r[3:2] != 2'b00;
            credit_amount      = (r[2] && r[3]) ? WIDTH'($random(seed))
                                                : WIDTH'(1 + {$random(seed)} % 3);
            clear_released     = r[5:4] == 2'b00;
            model_edge();
            @(negedge clk);
            check();
        end
        rst_n          = 1'b1;
        cfg_valid      = 1'b0;
        credit_valid   = 1'b0;
        clear_released = 1'b0;
    endtask

    initial begin
        done = 1'b0;
        seed = WIDTH;
        n_exact         = 0;
        n_beyond        = 0;
        n_zero          = 0;
        n_not_taken     = 0;
        n_arm_armed     = 0;
        n_clear_ignored = 0;
        n_one_credit    = 0;
        n_many_credits  = 0;
        m_armed    = 1'b0;
        m_released = 1'b0;
        m_target   = 0;
        m_sum      = 0;
        m_credits  = 0;
        rst_n              = 1'b0;
        cfg_valid          = 1'b0;
        cfg_waiting_amount = '0;
        credit_valid       = 1'b0;
        credit_amount      = '0;
        clear_released     = 1'b0;
        @(negedge clk);
        model_edge();
        @(negedge clk);
        check();
        random_test();
        if (n_exact == 0 || n_beyond == 0 || n_zero == 0 || n_not_taken == 0 || n_arm_armed == 0 ||
            n_clear_ignored == 0 || n_one_credit == 0 || n_many_credits == 0)
            $fatal(1, "Barrier %0d: a case did not happen: exact %0d beyond %0d zero %0d %s %0d %0d %0d %0d %0d",
                   WIDTH, n_exact, n_beyond, n_zero, "not taken, arm armed, clear, one, many",
                   n_not_taken, n_arm_armed, n_clear_ignored, n_one_credit, n_many_credits);
        done = 1'b1;
    end
endmodule

module TbCreditBarrier;
    wire clk;
    wire done_16;
    wire done_4;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbCreditBarrierCheck #(.WIDTH(16)) u_check_16(.clk, .done(done_16));
    TbCreditBarrierCheck #(.WIDTH(4))  u_check_4 (.clk, .done(done_4));

    initial begin
        wait (done_16 && done_4);
        $display("PASS");
        $finish;
    end
endmodule
