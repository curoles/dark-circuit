/* Test of Timer, with the behave or the struct library.
 *
 * A model of the timer: mtime and mtimecmp[h] as numbers, the irq of each hart as the compare
 * of the clock before. Random ticks (three clocks in four) and a request in most clocks,
 * held until taken: reads and writes of the low and high words of mtime and of every
 * mtimecmp, and of reserved addresses (msip, the word after the last mtimecmp, a word below
 * mtime), with random strobes (often all). Writes of mtimecmp mostly set it near mtime (a few
 * ticks before or after it, or the high word to mtime's), so that alarms are reached and
 * re-armed; one in eight sets it to all ones (no alarm). Writes of mtime sometimes set the
 * low word a few ticks below all ones, so that the low word carries into the high one. In
 * every clock: rsp_valid and rsp_rdata (a read answers one clock later with the word of the
 * clock it was taken, a reserved address with 0) and irq. After reset mtime is 0, mtimecmp all
 * ones, irq 0. N_HARTS 1 and 2; 20000 clocks on Verilator, 3000 on Icarus. Every case must
 * happen (checks named cover): an irq rising and falling for every hart, a write of mtime and
 * one in a clock with a tick (the write wins), a carry of the low word into the high one by a
 * tick, reads of every register word, a read of a reserved address. Checks named model and
 * cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbTimerCheck #(
    parameter N_HARTS = 1
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
`ifdef VERILATOR
    localparam N_CYCLES = 20000;
`else
    localparam N_CYCLES = 3000;
`endif
    localparam NW = 2 + 2 * N_HARTS;    // register words: mtime low, high; mtimecmp low, high

    logic               tick;
    wire  [N_HARTS-1:0] irq;
    logic               req_valid;
    wire                req_ready;
    logic               req_we;
    logic [15:0]        req_addr;
    logic [31:0]        req_wdata;
    logic [3:0]         req_wstrb;
    wire                rsp_valid;
    wire  [31:0]        rsp_rdata;

    logic [63:0]        m_time;                 // the model
    logic [63:0]        m_cmp [N_HARTS];
    logic [N_HARTS-1:0] m_irq;
    logic               m_rsp;                  // an answer is due now
    logic [31:0]        m_rdata;
    integer             seed;
    logic [N_HARTS-1:0] seen_rise, seen_fall;
    logic [NW-1:0]      seen_read;
    logic               seen_write_time, seen_write_tick, seen_carry, seen_reserved;

    Timer #(.N_HARTS(N_HARTS)) u_timer(
        .clk, .rst_n, .tick, .irq, .req_valid, .req_ready, .req_we, .req_addr, .req_wdata,
        .req_wstrb, .rsp_valid, .rsp_rdata);

    // The byte address of register word w (-1: a reserved address, picked at random).
    function automatic logic [15:0] addr_of(input int w);
        if (w == 0) return 16'(TimerPkg::MTIME);
        if (w == 1) return 16'(TimerPkg::MTIME + 4);
        return 16'(TimerPkg::MTIMECMP_BASE + 4 * (w - 2));
    endfunction

    // The register word at a byte address: 0 .. NW-1, or -1 for a reserved address (the
    // byte in the word does not matter).
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic int word_of(input logic [15:0] a);
        logic [15:0] t;
        for (int w = 0; w < NW; w++) begin
            t = addr_of(w);
            if (a[15:2] == t[15:2])
                return w;
        end
        return -1;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic logic [31:0] model_word(input int w);
        if (w == 0) return m_time[31:0];
        if (w == 1) return m_time[63:32];
        if (w > 1)  return (w % 2 == 0) ? m_cmp[(w - 2) / 2][31:0] : m_cmp[(w - 2) / 2][63:32];
        return '0;
    endfunction

    // A 64-bit value with the bytes of a word access merged in (word 0 low, 1 high).
    function automatic logic [63:0] merge(input logic [63:0] old, input int hi,
                                          input logic [31:0] data, input logic [3:0] strb);
        logic [63:0] v;
        v = old;
        for (int b = 0; b < 4; b++)
            if (strb[b])
                v[32 * hi + 8 * b +: 8] = data[8 * b +: 8];
        return v;
    endfunction

    // A new request.
    task automatic new_request;
        int    w;
        int    r;
        r = $unsigned($random(seed)) % 16;
        req_we    = ($random(seed) % 2) == 0;
        req_wstrb = ($random(seed) % 3 == 0) ? 4'($random(seed)) : 4'hf;
        req_wdata = $random(seed);
        if (r == 0) begin
            // A reserved address: msip, after the last mtimecmp, below mtime.
            case ($unsigned($random(seed)) % 3)
                0:       req_addr = 16'(TimerPkg::MSIP_BASE);
                1:       req_addr = 16'(TimerPkg::MTIMECMP_BASE + 8 * N_HARTS);
                default: req_addr = 16'(TimerPkg::MTIME - 8);
            endcase
            return;
        end
        w = (r < 4) ? (r % 2) : 2 + $unsigned($random(seed)) % (2 * N_HARTS);
        req_addr = addr_of(w);
        if (!req_we)
            return;
        if (w == 0 && $random(seed) % 4 == 0)
            req_wdata = 32'hffff_fff0 + 32'($unsigned($random(seed)) % 8);  // carries soon
        if (w > 1 && w % 2 == 0)
            req_wdata = m_time[31:0] + 32'($random(seed) % 24);     // near mtime
        if (w > 1 && w % 2 == 1)
            req_wdata = m_time[63:32];
        if (w > 1 && $random(seed) % 8 == 0)
            req_wdata = '1;                                          // no alarm
        if (w > 1)
            req_wstrb = 4'hf;
    endtask

    initial begin
        int w;
        logic taken;
        logic [31:0] low_before;    // mtime's low word before the edge
        done = 1'b0;
        {seen_rise, seen_fall, seen_read} = '0;
        {seen_write_time, seen_write_tick, seen_carry, seen_reserved} = '0;
        seed      = 7 * N_HARTS;
        tick      = 1'b0;
        req_valid = 1'b0;
        req_we    = 1'b0;
        req_addr  = '0;
        req_wdata = '0;
        req_wstrb = '0;
        m_time    = '0;
        for (int h = 0; h < N_HARTS; h++)
            m_cmp[h] = '1;
        m_irq     = '0;
        m_rsp     = 1'b0;
        m_rdata   = '0;
        @(posedge rst_n);
        taken = 1'b0;
        repeat (N_CYCLES) begin
            // The inputs of this clock, set at the falling edge: a request taken at the rising
            // edge before is withdrawn, a new one may come.
            @(negedge clk);
            if (taken)
                req_valid = 1'b0;
            tick = ($random(seed) % 4) != 0;
            if (!req_valid && ($random(seed) % 8) != 0) begin
                new_request();
                req_valid = 1'b1;
            end
            #1;
            if (irq !== m_irq || rsp_valid !== m_rsp || (m_rsp && rsp_rdata !== m_rdata))
                `DC_TEST_FAIL(model, $sformatf(
                    "Timer %0d: irq %b rsp %b %h, expected %b %b %h", N_HARTS, irq, rsp_valid,
                    rsp_rdata, m_irq, m_rsp, m_rdata))
            // The edge: the model, from the values of this clock.
            taken = req_valid && req_ready;
            w     = word_of(req_addr);
            for (int h = 0; h < N_HARTS; h++) begin
                if (!m_irq[h] && m_time >= m_cmp[h]) seen_rise[h] = 1'b1;
                if (m_irq[h] && m_time < m_cmp[h])   seen_fall[h] = 1'b1;
                m_irq[h] = m_time >= m_cmp[h];
            end
            m_rsp   = taken && !req_we;
            m_rdata = model_word(w);
            if (taken && !req_we && w >= 0) seen_read[w] = 1'b1;
            if (taken && w < 0)             seen_reserved = 1'b1;
            low_before = m_time[31:0];
            if (taken && req_we && w >= 0 && w < 2) begin
                m_time = merge(m_time, w, req_wdata, req_wstrb);
                seen_write_time = 1'b1;
                if (tick) seen_write_tick = 1'b1;
            end else if (tick) begin
                m_time = m_time + 1;
                if (low_before == '1) seen_carry = 1'b1;
            end
            if (taken && req_we && w >= 2)
                m_cmp[(w - 2) / 2] = merge(m_cmp[(w - 2) / 2], w % 2, req_wdata, req_wstrb);
        end
        if (seen_rise != '1 || seen_fall != '1 || seen_read != '1 || !seen_write_time ||
            !seen_write_tick || !seen_carry || !seen_reserved)
            `DC_TEST_FAIL(cover, $sformatf(
                "Timer %0d: rise %b fall %b read %b write %b write+tick %b carry %b reserved %b",
                N_HARTS, seen_rise, seen_fall, seen_read, seen_write_time, seen_write_tick,
                seen_carry, seen_reserved))
        done = 1'b1;
    end
endmodule

module TbTimer;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_1, done_2;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbTimerCheck #(.N_HARTS(1)) u_check_1(.clk, .rst_n, .done(done_1));
    TbTimerCheck #(.N_HARTS(2)) u_check_2(.clk, .rst_n, .done(done_2));

    initial begin
        wait (done_1 && done_2);
        $display("PASS");
        $finish;
    end
endmodule
