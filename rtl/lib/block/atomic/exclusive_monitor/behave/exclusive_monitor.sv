/* Exclusive monitor: the reservations of LR/SC (AXI's exclusive accesses) where every write
 * to a memory passes, one per agent (a core, a PE), behavioral (kb
 * rtl/lib/block/atomic/exclusive_monitor/design).
 *
 * A reservation is valid and a set: the address's bits from RESV_OFFSET up (a set of
 * 1 << RESV_OFFSET bytes: a word, or a cache line). The user calls it at the place every
 * request to the memory passes, in the order the memory takes them:
 * - reserve: an LR of reserve_agent the memory takes; the agent's reservation becomes its
 *   set (a reservation of another set is replaced: one per agent).
 * - write: a write of the memory's (a plain write, an atomic, a successful SC), from any
 *   agent; every reservation of its set ends, the writer's own too (the RISC-V spec allows
 *   it: a constrained LR/SC loop has no store between its LR and its SC).
 * - sc_ok: may an SC of sc_agent at sc_addr succeed: the agent's reservation is valid and
 *   of that set; combinational, so the user decides in the clock it asks.
 * - sc_done: the SC is decided (succeeded or failed); the agent's reservation ends. A
 *   successful SC is also a write (write with its address), in the same clock.
 * In one clock the ends come first, then the reservation: an LR taken with a write of its
 * set reserves after it. The user keeps the order of its requests and answers (an SC's
 * answer is its status); this block only remembers.
 *
 *   reserve, reserve_agent, reserve_addr --> resv[agent] = {valid, set}
 *   write, write_addr --------------------> resv[*] of that set end
 *   sc_agent, sc_addr --> resv[sc_agent] valid and of that set --> sc_ok
 *   sc_done --------------------------------> resv[sc_agent] ends
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module ExclusiveMonitor #(
    parameter  N_AGENTS    = 4,         // agents, a reservation each
    parameter  ADDR_WIDTH  = 32,        // byte address
    parameter  RESV_OFFSET = 2,         // a reservation is a set of 1 << RESV_OFFSET bytes
    localparam AGENT_WIDTH = (N_AGENTS > 1) ? $clog2(N_AGENTS) : 1
)(
    input  wire                   clk,
    input  wire                   rst_n,            // synchronous reset, active low: none
    // An LR the memory takes
    input  wire                   reserve,
    input  wire [AGENT_WIDTH-1:0] reserve_agent,
    // The offset in the set is not read.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [ADDR_WIDTH-1:0]  reserve_addr,
    // A write the memory takes, from any agent (an SC that succeeds too)
    input  wire                   write,
    input  wire [ADDR_WIDTH-1:0]  write_addr,
    // An SC: may it succeed; it is decided
    input  wire [AGENT_WIDTH-1:0] sc_agent,
    input  wire [ADDR_WIDTH-1:0]  sc_addr,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire                   sc_ok,            // its agent's reservation is of its set
    input  wire                   sc_done           // decided: its agent's reservation ends
);
    `DC_STATIC_ASSERT(a_sizes, N_AGENTS >= 1 && RESV_OFFSET < ADDR_WIDTH)

    typedef logic [ADDR_WIDTH-1:RESV_OFFSET] set_t;

    logic [N_AGENTS-1:0] valid;         // agent a's reservation holds
    set_t                set [N_AGENTS];    // ... of this set

    assign sc_ok = valid[sc_agent] && set[sc_agent] == sc_addr[ADDR_WIDTH-1:RESV_OFFSET];

    // The ends first, then the reservation.
    // @kb: rtl/lib/block/atomic/exclusive_monitor/design
    always_ff @(posedge clk)
        if (!rst_n)
            valid <= '0;
        else
            for (int a = 0; a < N_AGENTS; a++)
                if (reserve && int'(reserve_agent) == a)
                    valid[a] <= 1'b1;
                else if ((write && set[a] == write_addr[ADDR_WIDTH-1:RESV_OFFSET]) ||
                         (sc_done && int'(sc_agent) == a))
                    valid[a] <= 1'b0;

    // No reset: a set means nothing while its valid bit is 0.
    always_ff @(posedge clk)
        if (reserve)
            set[reserve_agent] <= reserve_addr[ADDR_WIDTH-1:RESV_OFFSET];

    // The agents are agents of the monitor.
    `DC_ASSERT(a_reserve_agent, !(reserve && int'(reserve_agent) >= N_AGENTS))
    `DC_ASSERT(a_sc_agent, !(sc_done && int'(sc_agent) >= N_AGENTS))

endmodule
