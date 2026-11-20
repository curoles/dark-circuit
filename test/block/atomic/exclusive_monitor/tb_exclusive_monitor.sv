/* Test of ExclusiveMonitor, behave version.
 *
 * The testbench is the place every request passes: in every clock a random mix of an LR (an
 * agent reserves), a write (any agent's, of a set), an SC (an agent asks; most SCs at its own
 * reservation, with other offset bits in the set) and nothing; a successful SC also writes,
 * a decided one ends its agent's reservation; now and then an LR and a write of the same set
 * in one clock. A model keeps every agent's reservation (valid, set) and why it last ended
 * (another agent's write, the agent's own write, its SC, a reservation replaced by another
 * set), and gives sc_ok in every clock. Configurations: 4 agents, words (RESV_OFFSET 2);
 * 3 agents, lines of 16 bytes (RESV_OFFSET 4). 20000 clocks on Verilator, 2000 on Icarus.
 * Every case must happen (checks named cover): an SC that succeeds, with other offset bits
 * than its LR's; one that fails after another agent's write, after the agent's own write,
 * after its earlier SC, with its reservation of another set; an LR and a write of its set
 * in one clock. Checks named model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbExclusiveMonitorCheck #(
    parameter N_AGENTS    = 4,
    parameter ADDR_WIDTH  = 16,
    parameter RESV_OFFSET = 2
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
`ifdef VERILATOR
    localparam N_CYCLES = 20000;
`else
    localparam N_CYCLES = 2000;
`endif
    localparam AGENT_WIDTH = (N_AGENTS > 1) ? $clog2(N_AGENTS) : 1;
    localparam SETS        = 4;         // the sets the addresses come from: they collide

    typedef enum int {
        WHY_NONE,                       // never reserved
        WHY_OTHER,                      // another agent wrote its set
        WHY_OWN,                        // the agent wrote its set
        WHY_DONE                        // its SC was decided
    } why_e;

    logic                   reserve;
    logic [AGENT_WIDTH-1:0] reserve_agent;
    logic [ADDR_WIDTH-1:0]  reserve_addr;
    logic                   write;
    logic [ADDR_WIDTH-1:0]  write_addr;
    logic [AGENT_WIDTH-1:0] sc_agent;
    logic [ADDR_WIDTH-1:0]  sc_addr;
    wire                    sc_ok;
    logic                   sc_done;
    integer                 seed;

    ExclusiveMonitor #(.N_AGENTS(N_AGENTS), .ADDR_WIDTH(ADDR_WIDTH),
                       .RESV_OFFSET(RESV_OFFSET)) u_exclusive_monitor(
        .clk, .rst_n, .reserve, .reserve_agent, .reserve_addr, .write, .write_addr,
        .sc_agent, .sc_addr, .sc_ok, .sc_done);

    // The model.
    logic                  m_valid [N_AGENTS];
    logic [ADDR_WIDTH-1:0] m_addr  [N_AGENTS];      // the LR's address (its set reserved)
    why_e                  m_why   [N_AGENTS];      // why it last ended
    logic [ADDR_WIDTH-1:0] base    [SETS];          // the sets' first bytes
    integer                n_ok, n_ok_offset, n_fail_other, n_fail_own, n_fail_done;
    integer                n_fail_set, n_same_clock;

    function automatic logic same_set(logic [ADDR_WIDTH-1:0] a, logic [ADDR_WIDTH-1:0] b);
        return (a >> RESV_OFFSET) == (b >> RESV_OFFSET);
    endfunction

    // An address in one of the sets, with random offset bits.
    function automatic logic [ADDR_WIDTH-1:0] random_addr();
        return base[{$random(seed)} % SETS] | ADDR_WIDTH'({$random(seed)} % (1 << RESV_OFFSET));
    endfunction

    function automatic logic m_sc_ok(logic [AGENT_WIDTH-1:0] a, logic [ADDR_WIDTH-1:0] addr);
        return m_valid[a] && same_set(m_addr[a], addr);
    endfunction

    // The inputs of the next clock.
    task automatic drive();
        integer k;
        k             = {$random(seed)} % 16;
        reserve       = k < 5 || k == 15;
        reserve_agent = AGENT_WIDTH'({$random(seed)} % N_AGENTS);
        reserve_addr  = random_addr();
        sc_agent      = AGENT_WIDTH'({$random(seed)} % N_AGENTS);
        sc_addr       = ({$random(seed)} % 4 != 0)
                        ? (m_addr[sc_agent] & ~ADDR_WIDTH'((1 << RESV_OFFSET) - 1))
                          | ADDR_WIDTH'({$random(seed)} % (1 << RESV_OFFSET))
                        : random_addr();
        sc_done       = k >= 8 && k < 13 && !reserve;
        write         = (k >= 5 && k < 8) || k == 15;
        write_addr    = (k == 15) ? reserve_addr : random_addr();
        // A successful SC writes its set, in the clock it is decided.
        if (sc_done && m_sc_ok(sc_agent, sc_addr)) begin
            write      = 1'b1;
            write_addr = sc_addr;
        end
    endtask

    initial begin
        logic               exp;
        logic [N_AGENTS-1:0] writer;    // the agents whose own write it is, this clock
        done = 1'b0;
        seed = N_AGENTS * 100 + RESV_OFFSET;
        {n_ok, n_ok_offset, n_fail_other, n_fail_own, n_fail_done} = '0;
        {n_fail_set, n_same_clock} = '0;
        for (int s = 0; s < SETS; s++)
            base[s] = ADDR_WIDTH'(s * 3 + 1) << RESV_OFFSET;
        for (int a = 0; a < N_AGENTS; a++) begin
            m_valid[a] = 1'b0;
            m_addr[a]  = base[0];
            m_why[a]   = WHY_NONE;
        end
        {reserve, write, sc_done} = '0;
        {reserve_agent, reserve_addr, write_addr, sc_agent, sc_addr} = '0;
        @(posedge rst_n);
        @(posedge clk);
        #1 drive();
        repeat (N_CYCLES) begin
            @(negedge clk);
            exp = m_sc_ok(sc_agent, sc_addr);
            if (sc_ok !== exp)
                `DC_TEST_FAIL(model, $sformatf(
                    "ExclusiveMonitor %0d/%0d: sc_ok %b for agent %0d at %h, expected %b",
                    N_AGENTS, RESV_OFFSET, sc_ok, sc_agent, sc_addr, exp))
            // The cases, at an SC decided.
            if (sc_done && exp) begin
                n_ok = n_ok + 1;
                if (sc_addr != m_addr[sc_agent]) n_ok_offset = n_ok_offset + 1;
            end else if (sc_done && m_valid[sc_agent])
                n_fail_set = n_fail_set + 1;
            else if (sc_done && m_why[sc_agent] == WHY_OTHER)
                n_fail_other = n_fail_other + 1;
            else if (sc_done && m_why[sc_agent] == WHY_OWN)
                n_fail_own = n_fail_own + 1;
            else if (sc_done && m_why[sc_agent] == WHY_DONE)
                n_fail_done = n_fail_done + 1;
            if (reserve && write && same_set(reserve_addr, write_addr))
                n_same_clock = n_same_clock + 1;
            // The edge: the ends first, then the reservation. A write is its own when an SC
            // of that agent writes; a plain write here has no agent, counted as another's.
            writer = '0;
            if (sc_done && exp) writer[sc_agent] = 1'b1;
            for (int a = 0; a < N_AGENTS; a++)
                if (m_valid[a] && write && same_set(m_addr[a], write_addr)) begin
                    m_valid[a] = 1'b0;
                    if (writer[a]) m_why[a] = WHY_OWN;
                    else           m_why[a] = WHY_OTHER;
                end
            if (sc_done && m_valid[sc_agent]) begin
                m_valid[sc_agent] = 1'b0;
                m_why[sc_agent]   = WHY_DONE;
            end
            if (reserve) begin
                m_valid[reserve_agent] = 1'b1;
                m_addr[reserve_agent]  = reserve_addr;
            end
            @(posedge clk);
            #1 drive();
        end
        if (n_ok == 0 || n_ok_offset == 0 || n_fail_other == 0 || n_fail_own == 0 ||
            n_fail_done == 0 || n_fail_set == 0 || n_same_clock == 0)
            `DC_TEST_FAIL(cover, $sformatf({
                "ExclusiveMonitor %0d/%0d: ok %0d (offset %0d), fail: other %0d own %0d ",
                "done %0d set %0d; same clock %0d"}, N_AGENTS, RESV_OFFSET, n_ok, n_ok_offset,
                n_fail_other, n_fail_own, n_fail_done, n_fail_set, n_same_clock))
        done = 1'b1;
    end
endmodule

module TbExclusiveMonitor;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_4, done_3;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbExclusiveMonitorCheck #(.N_AGENTS(4), .ADDR_WIDTH(16), .RESV_OFFSET(2)) u_check_4(
        .clk, .rst_n, .done(done_4));
    TbExclusiveMonitorCheck #(.N_AGENTS(3), .ADDR_WIDTH(12), .RESV_OFFSET(4)) u_check_3(
        .clk, .rst_n, .done(done_3));

    initial begin
        wait (done_4 && done_3);
        $display("PASS");
        $finish;
    end
endmodule
