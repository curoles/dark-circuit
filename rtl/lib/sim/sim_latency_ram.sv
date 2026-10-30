/* Simulation RAM with variable latency: SimRAM behind a request channel.
 *
 * The memory side of the caches (DirectCache): requests on a valid/ready channel (AGENTS.md),
 * req_we, the byte address of a word of DATA_SIZE bytes (the low bits are not used), for a
 * write the word and its byte strobes; a write gets no answer, a read is answered by
 * rsp_valid with the word one or more clocks after it was taken, in the order of the
 * requests (no ready: the requester always takes the answer). A model of what is behind a
 * cache (an L2, DRAM, a bus) or of a slow memory behind a core, for testing the logic that
 * waits for it.
 *
 * Memory order: a request does its work at the edge it is taken: a write writes, a read
 * reads its word then and keeps it until its answer is due; so a read sees every write taken
 * before it and none after it, whatever the latencies.
 * Latency of a read, drawn when it is taken: FAST_PERCENT of the reads take FAST_MIN to
 * FAST_MAX clocks, the others SLOW_MIN to SLOW_MAX (an L2 hit or not); an answer comes no
 * earlier than the clock after the answer before it. Up to MAX_PENDING reads wait for their
 * answers; a slot is free again in the clock its answer goes out, so with MAX_PENDING=1 and
 * latency 1 a read can be taken every clock. req_ready is 1 in READY_PERCENT of the clocks
 * (drawn a clock ahead: ready does not depend on the request) and while a slot is free.
 * FAST_PERCENT=100, FAST_MIN=FAST_MAX=1 and READY_PERCENT=100 make a memory of latency 1.
 * configure() sets READY_PERCENT and the latency mix at run time, the parameters being the
 * values until then: a testbench calls it at time 0 (for example with values of plusargs), so
 * one build runs with any of them; a later call takes effect from the next draw. MAX_PENDING
 * (the size of the queue) and SEED stay parameters.
 * Random numbers come from $random with SEED, from reset on: a run repeats.
 * load() and peek() as in SimRAM; rst_n empties the queue of reads, not the memory.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module SimLatencyRAM #(
    parameter  DATA_SIZE     = 4,               // bytes in a word: 1, 2, 4, 8, ...
    parameter  ADDR_WIDTH    = 16,              // byte address width
    parameter  MEM_SIZE      = 1 << ADDR_WIDTH, // bytes
    parameter  READY_PERCENT = 100,             // 1..100: clocks with req_ready=1 (a slot free)
    parameter  FAST_PERCENT  = 100,             // 0..100: reads with the fast latency
    parameter  FAST_MIN      = 1,               // clocks from a read taken to its answer
    parameter  FAST_MAX      = 1,
    parameter  SLOW_MIN      = 10,
    parameter  SLOW_MAX      = 20,
    parameter  MAX_PENDING   = 1,               // reads waiting for their answers
    parameter  SEED          = 1,
    localparam DATA_WIDTH    = 8 * DATA_SIZE,
    localparam ADDR_START    = $clog2(DATA_SIZE)
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low

    // Requests (a channel)
    input  wire                  req_valid,
    output wire                  req_ready,
    input  wire                  req_we,        // 1: write, 0: read
    // The offset in the word is not used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [ADDR_WIDTH-1:0] req_addr,      // byte address
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [DATA_WIDTH-1:0] req_wdata,
    input  wire [DATA_SIZE-1:0]  req_wstrb,     // byte i is written when req_wstrb[i] is 1

    // Answers to reads
    output wire                  rsp_valid,
    output wire [DATA_WIDTH-1:0] rsp_data
);
    `DC_STATIC_ASSERT(a_ready_percent, READY_PERCENT >= 1 && READY_PERCENT <= 100)
    `DC_STATIC_ASSERT(a_fast_percent, FAST_PERCENT >= 0 && FAST_PERCENT <= 100)
    `DC_STATIC_ASSERT(a_fast_latency, FAST_MIN >= 1 && FAST_MAX >= FAST_MIN)
    `DC_STATIC_ASSERT(a_slow_latency, SLOW_MIN >= 1 && SLOW_MAX >= SLOW_MIN)
    `DC_STATIC_ASSERT(a_max_pending, MAX_PENDING >= 1)

    // Formats of load(), for callers: u_mem.load(file, u_mem.VLOG_HEX_FORMAT).
    /* verilator lint_off UNUSEDPARAM */
    localparam VLOG_HEX_FORMAT = 0;
    localparam VLOG_BIN_FORMAT = 1;
    /* verilator lint_on UNUSEDPARAM */

    wire                   accept;          // a request is taken in this clock
    wire [ADDR_WIDTH-1:0]  word_addr;       // byte address of the first byte of the word
    logic                  ready_draw;      // the random part of req_ready, drawn a clock ahead
    longint                now;             // clocks since reset
    longint                last_due;        // clock of the answer of the last read taken
    integer                seed;
    // READY_PERCENT and the latency mix now: the parameters, or what configure() set.
    int                    ready_percent = READY_PERCENT;
    int                    fast_percent  = FAST_PERCENT;
    int                    fast_min      = FAST_MIN;
    int                    fast_max      = FAST_MAX;
    int                    slow_min      = SLOW_MIN;
    int                    slow_max      = SLOW_MAX;

    // The reads waiting for their answers: a ring of MAX_PENDING slots, the oldest at head.
    logic [DATA_WIDTH-1:0] q_data [MAX_PENDING];
    longint                q_due  [MAX_PENDING];   // the clock its answer goes out
    integer                head;
    integer                count;

    // The read port is not used: a read takes its word with peek() at the edge it is taken.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [DATA_WIDTH-1:0]  ram_rd_data;
    wire                   ram_rd_valid;
    /* verilator lint_on UNUSEDSIGNAL */

    SimRAM #(.DATA_SIZE(DATA_SIZE), .ADDR_WIDTH(ADDR_WIDTH), .MEM_SIZE(MEM_SIZE)) u_sim_ram(
        .clk,
        .rd_en(1'b0), .rd_addr(req_addr[ADDR_WIDTH-1:ADDR_START]),
        .wr_en(accept && req_we), .wr_addr(req_addr[ADDR_WIDTH-1:ADDR_START]),
        .wr_data(req_wdata), .wr_strb(req_wstrb),
        .rd_data(ram_rd_data), .rd_valid(ram_rd_valid));

    function automatic int load(string filename, int format);
        return u_sim_ram.load(filename, format);
    endfunction

    function automatic logic [7:0] peek(input logic [ADDR_WIDTH-1:0] byte_addr);
        return u_sim_ram.peek(byte_addr);
    endfunction

    // The word at a: its bytes, little-endian.
    function automatic logic [DATA_WIDTH-1:0] read_word(input logic [ADDR_WIDTH-1:0] a);
        logic [DATA_WIDTH-1:0] w;
        for (int i = 0; i < DATA_SIZE; i++)
            w[8*i +: 8] = u_sim_ram.peek(a + ADDR_WIDTH'(i));
        return w;
    endfunction

    // READY_PERCENT and the latency mix from now on, with the limits of the parameters.
    function automatic void configure(input int ready_pct, input int fast_pct, input int fast_lo,
                                      input int fast_hi, input int slow_lo, input int slow_hi);
        if (ready_pct < 1 || ready_pct > 100 || fast_pct < 0 || fast_pct > 100 ||
            fast_lo < 1 || fast_hi < fast_lo || slow_lo < 1 || slow_hi < slow_lo)
            $fatal(1, "%m: configure(%0d, %0d, %0d, %0d, %0d, %0d): a value out of its range",
                   ready_pct, fast_pct, fast_lo, fast_hi, slow_lo, slow_hi);
        ready_percent = ready_pct;
        fast_percent  = fast_pct;
        fast_min      = fast_lo;
        fast_max      = fast_hi;
        slow_min      = slow_lo;
        slow_max      = slow_hi;
    endfunction

    // A latency, drawn for a read: fast or slow, then uniform in its range.
    function automatic int latency();
        if ({$random(seed)} % 100 < fast_percent)
            return fast_min + {$random(seed)} % (fast_max - fast_min + 1);
        return slow_min + {$random(seed)} % (slow_max - slow_min + 1);
    endfunction

    assign word_addr = {req_addr[ADDR_WIDTH-1:ADDR_START], {ADDR_START{1'b0}}};
    assign rsp_valid = count != 0 && q_due[head] == now;
    assign rsp_data  = q_data[head];
    assign req_ready = ready_draw && (count < MAX_PENDING || rsp_valid);
    assign accept    = req_valid && req_ready;

    // @kb: rtl/lib/sim/sim_latency_ram
    always @(posedge clk)
        if (!rst_n) begin
            // seed is the state of $random, which every draw updates in place: blocking.
            /* verilator lint_off BLKSEQ */
            seed        = SEED;     // a reset starts the same random sequence again
            /* verilator lint_on BLKSEQ */
            now        <= 0;
            last_due   <= 0;
            head       <= 0;
            count      <= 0;
            ready_draw <= {$random(seed)} % 100 < ready_percent;
        end else begin
            longint due;
            now        <= now + 1;
            ready_draw <= {$random(seed)} % 100 < ready_percent;
            if (accept && !req_we) begin
                due = now + longint'(latency());
                if (due <= last_due)
                    due = last_due + 1;
                q_data[(head + count) % MAX_PENDING] <= read_word(word_addr);
                q_due[(head + count) % MAX_PENDING]  <= due;
                last_due <= due;
            end
            if (rsp_valid)
                head <= (head + 1) % MAX_PENDING;
            count <= count + (accept && !req_we ? 1 : 0) - (rsp_valid ? 1 : 0);
        end

    // The answer of the oldest read is never late: it goes out in its clock.
    `DC_ASSERT(a_answer_not_late, count == 0 || q_due[head] >= now)

endmodule
