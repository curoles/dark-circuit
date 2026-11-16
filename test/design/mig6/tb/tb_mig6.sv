/* Testbench of Mig6's PEs running a program, every PE the same program (SPMD).
 *
 * N_PES PEs (Mig6Pe), PE p with HART_ID p; for now without a network, each alone with its
 * local memory. Loads +hex=<file> into every PE's memory, releases reset and runs until every
 * hart has exited. Each PE's debugger (TbMig6Debugger) serves its semihosting calls. The
 * end of a run:
 * - an exit with a status other than 0 fails the run at once, whatever the other harts do;
 * - an exit with status 0 reports the hart's ID (hart_exited()): it must be below N_PES,
 *   not have exited before, and be the HART_ID of the PE that exited (PE p: p), else the run
 *   fails; when every hart ID 0 to N_PES - 1 has exited, the run passes;
 * - +max_cycles=<n> (default 100000) clocks without that end fail the run, naming the harts
 *   that have not exited.
 * Stops at the first failure with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig6;
    import Mig6Pkg::*;

    localparam N_PES = 1;               // PEs, PE p has HART_ID p

    logic             clk;
    logic             rst_n;
    integer           cycle;            // rising edges out of reset
    integer           max_cycles;
    logic [N_PES-1:0] exited;           // exited[h]: hart h has exited with status 0

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    for (genvar p = 0; p < N_PES; p++) begin : g_pe
        wire         halt;
        dbg_req_t    dbg_req;
        dbg_rsp_t    dbg_rsp;
        // The retire trace and the pipeline view: not used by this testbench yet.
        /* verilator lint_off UNUSEDSIGNAL */
        retire_t     retire;
        pipe_trace_t pipe_trace;
        /* verilator lint_on UNUSEDSIGNAL */

        Mig6Pe #(.HART_ID(word_t'(p))) u_pe(
            .clk, .rst_n, .halt, .retire, .pipe_trace, .dbg_req, .dbg_rsp);

        TbMig6Debugger #(.PE(p)) u_debugger(.clk, .rst_n, .halt, .dbg_rsp, .dbg_req);

        initial begin
            string hex;
            if (!$value$plusargs("hex=%s", hex))
                $fatal(1, "Mig6: plusarg +hex=<file> is missing");
            if (u_pe.load(hex) != 1)
                $fatal(1, "Mig6: PE %0d: load() of %s returned 0", p, hex);
        end
    end

    // A hart exited with status 0, from PE pe (TbMig6Debugger).
    task automatic hart_exited(input int pe, input word_t hart);
        if (hart >= N_PES)
            $fatal(1, "Mig6: PE %0d exited as hart %0d, only %0d harts", pe, hart, N_PES);
        if (exited[hart])
            $fatal(1, "Mig6: PE %0d exited as hart %0d, which has exited before", pe, hart);
        if (hart != word_t'(pe))
            $fatal(1, "Mig6: PE %0d exited as hart %0d, its HART_ID is %0d", pe, hart, pe);
        exited[hart] = 1'b1;
        $display("Mig6: hart %0d exited (%0d of %0d)", hart, $countones(exited), N_PES);
        if (&exited) begin
            $display("PASS: %0d harts exited in %0d cycles", N_PES, cycle);
            $finish;
        end
    endtask

    // The harts that have not exited, for the failure message.
    function automatic string missing();
        string s;
        s = "";
        for (int h = 0; h < N_PES; h++)
            if (!exited[h])
                s = {s, $sformatf(" %0d", h)};
        return s;
    endfunction

    always @(posedge clk)
        if (rst_n) begin
            cycle <= cycle + 1;
            if (cycle >= max_cycles)
                $fatal(1, "Mig6: no end after %0d cycles (+max_cycles), harts not exited:%s",
                       max_cycles, missing());
        end

    initial begin
        cycle  = 0;
        exited = '0;
        if (!$value$plusargs("max_cycles=%d", max_cycles))
            max_cycles = 100000;
    end
endmodule
