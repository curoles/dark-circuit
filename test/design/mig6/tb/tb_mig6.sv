/* Testbench of Mig6's PEs running a program, every PE the same program (SPMD).
 *
 * Mig6 (u_mig6): its N_PES PEs, PE p with HART_ID p (Mig6PeGrid), and the shared memory.
 * Loads +hex=<file> into every PE's local memory, releases reset and runs until every hart
 * has exited. Each PE's debugger (TbMig6Debugger) serves its semihosting calls and prints
 * its PE's output a line at a time, each line with the hart's prefix, "[hart <n>] ", so that
 * lines of PEs running at once never mix. The end of a run:
 * - an exit with a status other than 0 fails the run at once, whatever the other harts do;
 * - an exit with status 0 reports the hart's ID (hart_exited()): it must be below N_PES,
 *   not have exited before, and be the HART_ID of the PE that exited (PE p: p), else the run
 *   fails; when every hart ID 0 to N_PES - 1 has exited, the run passes;
 * - +max_cycles=<n> (default 100000) clocks without that end fail the run, naming the harts
 *   that have not exited.
 * Every failure goes through fail(): failing tells the debuggers to print what is left in
 * their line buffers, then $fatal stops the run (Verilator runs no final block after a
 * $fatal).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig6;
    import Mig6Pkg::*;

    localparam N_PES = Mig6NocPkg::N_PES;   // PEs, PE p has HART_ID p

    logic                    clk;
    logic                    rst_n;
    integer                  cycle;         // rising edges out of reset
    integer                  max_cycles;
    logic        [N_PES-1:0] exited;        // exited[h]: hart h has exited with status 0
    logic                    failing;       // a failure is being reported
    wire         [N_PES-1:0] halt;
    dbg_req_t    [N_PES-1:0] dbg_req;
    dbg_rsp_t    [N_PES-1:0] dbg_rsp;
    // The retire trace and the pipeline view: not used by this testbench yet.
    /* verilator lint_off UNUSEDSIGNAL */
    retire_t     [N_PES-1:0] retire;
    pipe_trace_t [N_PES-1:0] pipe_trace;
    /* verilator lint_on UNUSEDSIGNAL */

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    Mig6 u_mig6(.clk, .rst_n, .halt, .retire, .pipe_trace, .dbg_req, .dbg_rsp);

    for (genvar p = 0; p < N_PES; p++) begin : g_pe
        TbMig6Debugger #(.PE(p), .HART_ID(word_t'(p))) u_debugger(
            .clk, .rst_n, .halt(halt[p]), .dbg_rsp(dbg_rsp[p]), .dbg_req(dbg_req[p]));

        initial begin
            string hex;
            if (!$value$plusargs("hex=%s", hex))
                $fatal(1, "Mig6: plusarg +hex=<file> is missing");
            if (u_mig6.u_grid.g_pe[p].u_pe.load(hex) != 1)
                $fatal(1, "Mig6: PE %0d: load() of %s returned 0", p, hex);
        end
    end

    // Fail the run: the debuggers print what is left in their line buffers first.
    task automatic fail(input string msg);
        failing = 1'b1;
        #1;
        $fatal(1, "%s", msg);
    endtask

    // A hart exited with status 0, from PE pe (TbMig6Debugger). While a failure is being
    // reported (the clock fail() waits for the debuggers), other exits are ignored.
    task automatic hart_exited(input int pe, input word_t hart);
        if (failing)
            return;
        if (hart >= N_PES)
            fail($sformatf("Mig6: PE %0d exited as hart %0d, only %0d harts", pe, hart, N_PES));
        if (exited[hart])
            fail($sformatf("Mig6: PE %0d exited as hart %0d, which has exited before", pe,
                           hart));
        if (hart != word_t'(pe))
            fail($sformatf("Mig6: PE %0d exited as hart %0d, its HART_ID is %0d", pe, hart,
                           pe));
        if (failing)
            return;
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
        if (rst_n && !failing) begin
            cycle <= cycle + 1;
            if (cycle >= max_cycles)
                fail($sformatf("Mig6: no end after %0d cycles (+max_cycles), harts not exited:%s",
                               max_cycles, missing()));
        end

    initial begin
        cycle   = 0;
        exited  = '0;
        failing = 1'b0;
        if (!$value$plusargs("max_cycles=%d", max_cycles))
            max_cycles = 100000;
    end
endmodule
