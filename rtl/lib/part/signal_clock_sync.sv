/* Signal clock synchronizer: brings in, a signal of clk1's clock domain, into clk2's domain,
 * through a chain of STAGES flip-flops on clk2.
 *
 * A signal of another clock can change at any time, also right at a rising edge of clk2; the
 * first flop that samples it may then go metastable (neither 0 nor 1 for a while). The flops
 * after it give that time to settle, so out is a clean level of clk2's domain: STAGES = 2 is
 * the usual choice, 3 for fast clocks or a long life. What crosses must come straight from a
 * flop, never from logic, which can glitch (a glitch caught by clk2 is a value that never
 * was): with SRC_FLOP = 1 the part first registers in on clk1; with SRC_FLOP = 0 in must
 * already be a flop's output (clk1 is then not used).
 *
 * out follows in after SRC_FLOP edges of clk1 and STAGES (or STAGES + 1, when an edge of clk2
 * comes too close to the change) edges of clk2; a change of in shorter than a period of clk2
 * may be missed (a pulse needs a pulse synchronizer). WIDTH > 1 synchronizes each bit on its
 * own: when several bits change together they may arrive in different clocks of clk2, so out
 * can show a value in never had. Safe only for independent bits, a Gray-coded counter (one bit
 * changes at a time) or a value held long enough before it is read; data needs a handshake or
 * an asynchronous FIFO. No reset: out is unknown for the first STAGES edges of clk2. In a real
 * flow the chain's flops are marked for the tools (not to be merged, moved or retimed; e.g.
 * ASYNC_REG on FPGAs) and the path from clk1 to clk2 gets a timing exception; the library has
 * no convention for either yet.
 *
 *            clk1 domain              |              clk2 domain
 *   in --> [Dff clk1] (SRC_FLOP) --> chain[0] --> [Dff clk2] --> ... --> [Dff clk2] --> out
 *                                     |          chain[1]  ...  chain[STAGES]
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module SignalClockSync #(
    parameter WIDTH    = 1,
    parameter STAGES   = 2,         // flops on clk2: 2 or more
    parameter SRC_FLOP = 1          // 1: register in on clk1 first; 0: in is a flop's output
)(
    // clk1 is in's clock; with SRC_FLOP = 0 nothing here uses it.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire             clk1,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire             clk2,
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);
    `DC_STATIC_ASSERT(a_min_stages, STAGES >= 2)

    wire [STAGES:0][WIDTH-1:0] chain;   // chain[0] crosses into clk2's domain; out is the last

    if (SRC_FLOP) begin: g_src_flop
        Dff #(.WIDTH(WIDTH)) u_dff_src(.clk(clk1), .in, .out(chain[0]));
    end else begin: g_src_wire
        assign chain[0] = in;
    end

    for (genvar i = 0; i < STAGES; i++) begin: g_stage
        Dff #(.WIDTH(WIDTH)) u_dff(.clk(clk2), .in(chain[i]), .out(chain[i + 1]));
    end

    assign out = chain[STAGES];

endmodule
