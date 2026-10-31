/* Test of NocVirtChOut.
 *
 * A VC allocator gives the free VC to a packet now and then; a switch allocator sends its flits
 * while there are credits, the last one as the tail (packets of 1 to 4 flits); the receiver
 * returns a credit for a flit it holds in most clocks. A model keeps the credits and whether the
 * VC is taken; every clock free and has_credit must be the model's. Every case must happen: no
 * credit left, all credits back, a send and a credit in one clock, an alloc in the clock after
 * a tail (BUF_DEPTH > 1 for the send and the credit). BUF_DEPTH 3 and 1; Verilator 20000
 * clocks, Icarus 2000. Stops at the first mismatch
 * with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbNocVirtChOutCheck #(
    parameter BUF_DEPTH = 3
)(
    input  wire  clk,
    output logic done
);
`ifdef VERILATOR
    localparam N_CLOCKS = 20000;
`else
    localparam N_CLOCKS = 2000;
`endif

    logic                  rst_n;
    logic                  alloc;
    logic                  send;
    logic                  send_tail;
    logic                  credit;
    NocPkg::vc_out_state_t state;

    NocVirtChOut #(.BUF_DEPTH(BUF_DEPTH)) u_virt_ch_out(
        .clk, .rst_n, .alloc, .send, .send_tail, .credit, .state);

    // Model.
    integer credits;
    logic   taken;
    integer left;           // flits of the packet still to send
    logic   tail_before;    // the clock before sent a tail
    integer seed;

    // Cases seen.
    integer n_no_credit;
    integer n_all_back;
    integer n_send_credit;
    integer n_alloc_after_tail;

    task automatic drive;
        alloc     = 1'b0;
        send      = 1'b0;
        send_tail = 1'b0;
        credit    = 1'b0;
        if (!taken && {$random(seed)} % 3 == 0)
            alloc = 1'b1;
        if (taken && credits > 0 && {$random(seed)} % 10 < 7) begin
            send      = 1'b1;
            send_tail = (left == 1);
        end
        if (credits < BUF_DEPTH && {$random(seed)} % 10 < 6)
            credit = 1'b1;
    endtask

    task automatic check;
        if (state.free !== !taken || state.has_credit !== (credits > 0))
            $fatal(1, "NocVirtChOut %0d: free %b has_credit %b, expected %b %b", BUF_DEPTH,
                   state.free, state.has_credit, !taken, credits > 0);
        if (credits == 0)         n_no_credit = n_no_credit + 1;
        if (credits == BUF_DEPTH) n_all_back  = n_all_back + 1;
    endtask

    task automatic model_edge;
        if (alloc && tail_before)
            n_alloc_after_tail = n_alloc_after_tail + 1;
        if (send && credit)
            n_send_credit = n_send_credit + 1;
        tail_before = send && send_tail;
        if (alloc) begin
            taken = 1'b1;
            left  = 1 + {$random(seed)} % 4;
        end
        if (send) begin
            credits = credits - 1;
            left    = left - 1;
            if (send_tail)
                taken = 1'b0;
        end
        if (credit)
            credits = credits + 1;
    endtask

    initial begin
        done               = 1'b0;
        seed               = BUF_DEPTH * 11;
        credits            = BUF_DEPTH;
        taken              = 1'b0;
        left               = 0;
        tail_before        = 1'b0;
        n_no_credit        = 0;
        n_all_back         = 0;
        n_send_credit      = 0;
        n_alloc_after_tail = 0;
        rst_n              = 1'b0;
        alloc              = 1'b0;
        send               = 1'b0;
        send_tail          = 1'b0;
        credit             = 1'b0;
        @(negedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        for (int k = 0; k < N_CLOCKS; k++) begin
            drive();
            #1;
            check();
            model_edge();
            @(negedge clk);
        end
        // With one credit a send and a credit can not meet: the credit needs the flit sent.
        if (n_no_credit == 0 || n_all_back == 0 || (BUF_DEPTH > 1 && n_send_credit == 0) ||
            n_alloc_after_tail == 0)
            $fatal(1, "NocVirtChOut %0d: cases: no credit %0d, back %0d, send+credit %0d, %0d",
                   BUF_DEPTH, n_no_credit, n_all_back, n_send_credit, n_alloc_after_tail);
        done = 1'b1;
    end
endmodule

module TbNocVirtChOut;
    wire clk;
    wire done_3;
    wire done_1;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbNocVirtChOutCheck #(.BUF_DEPTH(3)) u_check_3(.clk, .done(done_3));
    TbNocVirtChOutCheck #(.BUF_DEPTH(1)) u_check_1(.clk, .done(done_1));

    initial begin
        wait (done_3 && done_1);
        $display("PASS");
        $finish;
    end
endmodule
