/* Test of DmaEngine (with DmaChannel and DmaMover), with the behave or the struct library.
 *
 * The testbench drives every channel and is the memory. Each channel runs random transfers in
 * its own part of the memory (so the result does not depend on how the channels interleave):
 * 0 to 60 bytes, source and destination anywhere in the part (they may overlap), a random
 * gap between transfers; in one transfer of six a stop at a random clock. Per channel, the
 * clock after a start: busy, or done for 0 bytes; at the end: done with nothing left and the
 * addresses past the last byte, or (stopped) idle with bytes left and the addresses that far.
 * The memory is ready in 70 % of the clocks and answers 1 to 4 clocks late. Model: a
 * reference memory where a transfer's transactions are replayed (n counted byte by byte as
 * the mover does, each copied from a snapshot) up to the bytes the channel moved, which must
 * end at a transaction. Every clock: an offer to the mover that waits stays the same. At the
 * end the memory equals the reference. Configurations: 3 channels with beats of 64 bits, 1
 * channel with 32. Every case must happen (checks named cover): two channels offering at
 * once, an offer that waits, a stop, a transfer of 0 bytes, each channel done. Checks named
 * model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbDmaEngineCheck #(
    parameter N_CHANNELS = 3,
    parameter DATA_WIDTH = 64
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done_all
);
`ifdef VERILATOR
    localparam N_XFERS = 60;            // transfers a channel
`else
    localparam N_XFERS = 15;
`endif
    localparam N       = N_CHANNELS;
    localparam AW      = 11;            // a memory of 2 KiB
    localparam MEM     = 1 << AW;
    localparam PART    = MEM / N;       // each channel's part
    localparam LW      = 12;
    localparam B       = DATA_WIDTH / 8;
    localparam MAX_LEN = 60;
    localparam LIMIT   = 400 * N;       // clocks a transfer may take
    localparam IW      = (N > 1) ? $clog2(N) : 1;

    typedef enum int {GAP, STARTED, RUN} phase_e;

    logic [N-1:0]          start;
    logic [N-1:0][AW-1:0]  start_src, start_dst;
    logic [N-1:0][LW-1:0]  start_len;
    logic [N-1:0]          stop;
    wire  [N-1:0]          busy, done;
    wire  [N-1:0][AW-1:0]  cur_src, cur_dst;
    wire  [N-1:0][LW-1:0]  left;
    wire                   mem_req_valid;
    logic                  mem_req_ready;
    wire                   mem_req_we;
    wire  [AW-1:0]         mem_req_addr;
    // Checked by the DmaMover test.
    /* verilator lint_off UNUSEDSIGNAL */
    wire  [2:0]            mem_req_size;
    /* verilator lint_on UNUSEDSIGNAL */
    wire  [DATA_WIDTH-1:0] mem_req_wdata;
    wire  [B-1:0]          mem_req_wstrb;
    logic                  mem_rsp_valid;
    logic [DATA_WIDTH-1:0] mem_rsp_data;

    logic [7:0]            mem [MEM];
    logic [7:0]            ref_mem [MEM];
    logic [DATA_WIDTH-1:0] ans [$];
    int                    due [$];
    int                    cycle;
    integer                seed;
    bit                    seen_two, seen_wait, seen_stop, seen_empty;
    logic [N-1:0]          seen_done;

    DmaEngine #(.N_CHANNELS(N), .ADDR_WIDTH(AW), .DATA_WIDTH(DATA_WIDTH), .LEN_WIDTH(LW))
        u_dma_engine(
            .clk, .rst_n, .start, .start_src, .start_dst, .start_len, .stop, .busy, .done,
            .cur_src, .cur_dst, .left, .mem_req_valid, .mem_req_ready, .mem_req_we,
            .mem_req_addr, .mem_req_size, .mem_req_wdata, .mem_req_wstrb, .mem_rsp_valid,
            .mem_rsp_data);

    function automatic logic [DATA_WIDTH-1:0] beat_at(input logic [AW-1:0] a);
        logic [DATA_WIDTH-1:0] d;
        for (int k = 0; k < B; k++)
            d[8 * k +: 8] = mem[int'(a) + k];
        return d;
    endfunction

    // Replay a transfer's transactions on the reference up to moved bytes: 1 when they end
    // exactly there.
    function automatic bit replay(input int s, input int d, input int len, input int moved);
        int         left_b, n;
        logic [7:0] snap [B];
        left_b = len;
        while (len - left_b < moved) begin
            n = 0;
            while (n < left_b && (s + n) / B == s / B && (d + n) / B == d / B)
                n++;
            for (int i = 0; i < n; i++)
                snap[i] = ref_mem[s + i];
            for (int i = 0; i < n; i++)
                ref_mem[d + i] = snap[i];
            s      += n;
            d      += n;
            left_b -= n;
        end
        return len - left_b == moved;
    endfunction

    // The memory, as in the DmaMover test.
    initial begin
        mem_req_ready = 1'b0;
        mem_rsp_valid = 1'b0;
        mem_rsp_data  = '0;
        cycle         = 0;
        forever begin
            @(negedge clk);
            cycle++;
            mem_req_ready = $unsigned($random(seed)) % 10 < 7;
            mem_rsp_valid = ans.size() > 0 && due[0] <= cycle;
            mem_rsp_data  = mem_rsp_valid ? ans[0] : '0;
            #1;
            if (rst_n && mem_req_valid && mem_req_ready) begin
                if (mem_req_we) begin
                    for (int k = 0; k < B; k++)
                        if (mem_req_wstrb[k])
                            mem[int'(mem_req_addr) + k] = mem_req_wdata[8 * k +: 8];
                end else begin
                    ans.push_back(beat_at(mem_req_addr));
                    due.push_back(cycle + 1 + $unsigned($random(seed)) % 4);
                end
            end
            if (mem_rsp_valid) begin
                void'(ans.pop_front());
                void'(due.pop_front());
            end
        end
    end

    // The channels: one process, a state per channel.
    initial begin
        phase_e phase [N];
        int     gap [N], s [N], d [N], len [N], age [N], stop_at [N], xfers [N];
        int     moved, n_done;
        logic   prev_offer;
        logic [IW-1:0] prev_id;
        logic [2 * AW + LW - 1:0] prev_cmd;
        done_all = 1'b0;
        seed     = 13 * N + DATA_WIDTH;
        {seen_two, seen_wait, seen_stop, seen_empty} = '0;
        seen_done = '0;
        start = '0;
        stop  = '0;
        start_src = '0;
        start_dst = '0;
        start_len = '0;
        for (int a = 0; a < MEM; a++) begin
            mem[a]     = 8'($random(seed));
            ref_mem[a] = mem[a];
        end
        for (int c = 0; c < N; c++) begin
            phase[c] = GAP;
            gap[c]   = 1 + c;
            xfers[c] = 0;
        end
        prev_offer = 1'b0;
        prev_id    = '0;
        prev_cmd   = '0;
        @(posedge rst_n);
        n_done = 0;
        while (n_done < N) begin
            @(negedge clk);
            #2;     // after the memory's inputs
            // An offer that waited stays the same.
            if (prev_offer && (!u_dma_engine.mv_cmd_valid || u_dma_engine.cmd_id !== prev_id ||
                               u_dma_engine.cmd !== prev_cmd))
                `DC_TEST_FAIL(model, $sformatf("DmaEngine %0d: a waiting offer changed", N))
            if ($countones(u_dma_engine.req) > 1)                  seen_two  = 1'b1;
            prev_offer = u_dma_engine.mv_cmd_valid && !u_dma_engine.mv_cmd_ready;
            if (prev_offer)                                         seen_wait = 1'b1;
            prev_id    = u_dma_engine.cmd_id;
            prev_cmd   = u_dma_engine.cmd;
            start = '0;
            stop  = '0;
            n_done = 0;
            for (int c = 0; c < N; c++) begin
                case (phase[c])
                    GAP: if (xfers[c] == N_XFERS) begin
                        n_done++;
                    end else if (gap[c] > 1) begin
                        gap[c] = gap[c] - 1;
                    end else begin
                        len[c] = ($random(seed) % 10 == 0) ? 0
                                                           : 1 + $unsigned($random(seed)) % MAX_LEN;
                        s[c] = c * PART + $unsigned($random(seed)) % (PART - MAX_LEN);
                        d[c] = ($random(seed) % 4 == 0)
                               ? c * PART + $unsigned($random(seed)) % (PART - MAX_LEN)
                               : s[c] + $unsigned($random(seed)) % 12;
                        if (d[c] > c * PART + PART - MAX_LEN)
                            d[c] = s[c];
                        stop_at[c] = ($random(seed) % 6 == 0) ? 1 + $unsigned($random(seed)) % 40
                                                              : -1;
                        start[c]     = 1'b1;
                        start_src[c] = AW'(s[c]);
                        start_dst[c] = AW'(d[c]);
                        start_len[c] = LW'(len[c]);
                        age[c]       = 0;
                        phase[c]     = STARTED;
                    end
                    STARTED: begin
                        if (len[c] == 0 && (!done[c] || busy[c]))
                            `DC_TEST_FAIL(model, $sformatf(
                                "DmaEngine %0d: channel %0d: 0 bytes, done %b busy %b", N, c,
                                done[c], busy[c]))
                        if (len[c] != 0 && !busy[c])
                            `DC_TEST_FAIL(model, $sformatf(
                                "DmaEngine %0d: channel %0d: not busy after a start", N, c))
                        if (len[c] == 0) begin
                            seen_empty = 1'b1;
                            xfers[c]++;
                            gap[c]   = 1 + $unsigned($random(seed)) % 8;
                            phase[c] = GAP;
                        end else
                            phase[c] = RUN;
                    end
                    default: begin
                        age[c]++;
                        if (age[c] == stop_at[c])
                            stop[c] = 1'b1;
                        if (age[c] > LIMIT)
                            `DC_TEST_FAIL(model, $sformatf(
                                "DmaEngine %0d: channel %0d: no end after %0d clocks", N, c,
                                LIMIT))
                        if (!busy[c]) begin
                            moved = len[c] - int'(left[c]);
                            if (done[c] ? left[c] != 0 : (left[c] == 0 || stop_at[c] < 0))
                                `DC_TEST_FAIL(model, $sformatf(
                                    "DmaEngine %0d: channel %0d: done %b left %0d stop at %0d",
                                    N, c, done[c], left[c], stop_at[c]))
                            if (int'(cur_src[c]) != s[c] + moved ||
                                int'(cur_dst[c]) != d[c] + moved)
                                `DC_TEST_FAIL(model, $sformatf(
                                    "DmaEngine %0d: ch %0d: at %h %h after %0d bytes from %h %h",
                                    N, c, cur_src[c], cur_dst[c], moved, s[c], d[c]))
                            if (!replay(s[c], d[c], len[c], moved))
                                `DC_TEST_FAIL(model, $sformatf(
                                    "DmaEngine %0d: ch %0d: stopped inside a transaction (%0d)",
                                    N, c, moved))
                            if (done[c]) seen_done[c] = 1'b1;
                            else         seen_stop    = 1'b1;
                            xfers[c]++;
                            gap[c]   = 1 + $unsigned($random(seed)) % 8;
                            phase[c] = GAP;
                        end
                    end
                endcase
            end
        end
        repeat (8) @(negedge clk);
        for (int a = 0; a < MEM; a++)
            if (mem[a] !== ref_mem[a])
                `DC_TEST_FAIL(model, $sformatf("DmaEngine %0d: byte %h is %h, expected %h", N,
                                               a, mem[a], ref_mem[a]))
        if ((N > 1 && !seen_two) || (N > 1 && !seen_wait) || !seen_stop || !seen_empty ||
            seen_done != '1)
            `DC_TEST_FAIL(cover, $sformatf(
                "DmaEngine %0d: two %b wait %b stop %b empty %b done %b", N, seen_two,
                seen_wait, seen_stop, seen_empty, seen_done))
        done_all = 1'b1;
    end
endmodule

module TbDmaEngine;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_3, done_1;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbDmaEngineCheck #(.N_CHANNELS(3), .DATA_WIDTH(64)) u_check_3(.clk, .rst_n, .done_all(done_3));
    TbDmaEngineCheck #(.N_CHANNELS(1), .DATA_WIDTH(32)) u_check_1(.clk, .rst_n, .done_all(done_1));

    initial begin
        wait (done_3 && done_1);
        $display("PASS");
        $finish;
    end
endmodule
