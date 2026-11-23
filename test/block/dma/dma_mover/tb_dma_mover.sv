/* Test of DmaMover, behave or struct version.
 *
 * The testbench is the requester (a DMA channel) and the memory behind the mover's read and
 * write channels. The requester runs random transfers (source, destination, 1 to 80 bytes),
 * one transaction a command, offered back to back: it computes each transaction's n itself
 * (the bytes counted one by one while both stay in their beats, or, when both start at a
 * beat's start, while the source stays in its block of MAX_BURST beats; at most the bytes
 * left), advances by it at the take and remembers {ID, n, source, destination}; the mover
 * keeps up to DEPTH in flight. Like software, a new transfer starts after the last one's
 * dones; with MAX_BURST more than 1, half of them from aligned addresses. Every done must
 * come in command order with the remembered ID and n, and with WR_ACK only after the answer
 * to its last beat's write (the n-th done after the n-th such answer). A read must ask for
 * (n - 1) / BEAT + 1 beats (rd_req_len). The memory takes reads and writes in 70 % of the
 * clocks each, answers each beat of a read with its bytes as they were at the read, the
 * first 1 to 4 clocks later, the others after it, writes the strobed bytes at the clock it
 * takes a write, and with WR_ACK answers each write 1 to 3 clocks later; both answer in
 * order. Model: a reference memory
 * where each transaction, at its done, copies its n bytes from a snapshot of the source. With
 * DEPTH 1 a transfer may overlap itself (each read waits for the write before it, so the
 * mover copies the old bytes as the model does); with more, reads run ahead and overlapping
 * transfers are undefined, so none is made. At the end the memory equals the reference.
 * Configurations: beats of 32, 64 and 128 bits with DEPTH 1; 32 with DEPTH 4 and WR_ACK; 64
 * with DEPTH 8; bursts: 32 with DEPTH 4, MAX_BURST 4 and WR_ACK, 64 with DEPTH 8 and
 * MAX_BURST 8; 300 transfers each on Verilator, 60 on Icarus. Every case must happen (checks
 * named cover): a transaction cut by the bytes left, by the source's beat, by the
 * destination's beat, a whole beat, equal offsets that are not 0; with DEPTH 1 an
 * overlapping transfer; with more, DEPTH transactions in flight, and a read and a write
 * taken in the same clock; with bursts, a burst of MAX_BURST beats and one cut by the end of
 * its block. Checks named model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbDmaMoverCheck #(
    parameter DATA_WIDTH = 64,
    parameter DEPTH      = 1,
    parameter WR_ACK     = 0,
    parameter MAX_BURST  = 1
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
`ifdef VERILATOR
    localparam N_TRANSFERS = 300;
`else
    localparam N_TRANSFERS = 60;
`endif
    localparam AW      = 10;                    // a memory of 1 KiB
    localparam MEM     = 1 << AW;
    localparam IW      = 2;
    localparam B       = DATA_WIDTH / 8;        // bytes of a beat
    localparam OW      = $clog2(B);
    localparam MAX_LEN = 80;
    localparam BB      = $clog2(MAX_BURST);
    localparam LW      = (BB > 0) ? BB : 1;
    localparam NW      = OW + BB + 1;           // bits of n
    localparam BLOCK   = B * MAX_BURST;         // bytes of a burst's block
    localparam NAME    = DATA_WIDTH * 1000 + DEPTH * 10 + WR_ACK +     // in messages
                         ((MAX_BURST > 1) ? MAX_BURST * 1000000 : 0);

    typedef struct packed {             // packed: Icarus has no unpacked structs
        logic [IW-1:0] id;
        int            n, s, d;
    } xact_t;

    logic                  cmd_valid;
    wire                   cmd_ready;
    logic [IW-1:0]         cmd_id;
    logic [AW-1:0]         cmd_src, cmd_dst;
    logic [NW-1:0]         cmd_n;
    wire                   done_valid;
    wire  [IW-1:0]         done_id;
    wire  [NW-1:0]         done_n;
    wire                   rd_req_valid;
    logic                  rd_req_ready;
    wire  [AW-1:0]         rd_req_addr;
    wire  [2:0]            rd_req_size;
    wire  [LW-1:0]         rd_req_len;
    logic                  rd_rsp_valid;
    logic [DATA_WIDTH-1:0] rd_rsp_data;
    wire                   wr_req_valid;
    logic                  wr_req_ready;
    wire  [AW-1:0]         wr_req_addr;
    wire  [2:0]            wr_req_size;
    wire  [DATA_WIDTH-1:0] wr_req_wdata;
    wire  [B-1:0]          wr_req_wstrb;
    wire                   wr_req_rsp;
    logic                  wr_rsp_valid;

    logic [7:0]            mem [MEM];           // the memory
    logic [7:0]            ref_mem [MEM];       // the reference
    logic [DATA_WIDTH-1:0] ans [$];             // read answers due, in order
    int                    ans_due [$];         // ... their clocks
    int                    ack_due [$];         // write answers due (WR_ACK)
    bit                    ack_last [$];        // ... of a transaction's last beat
    int                    beats_q [$];         // the beats of the transactions not written
    int                    wbeats;              // ... of the oldest written so far
    // A queue of vectors: Icarus has no queues of structs (packed structs convert to and from).
    logic [$bits(xact_t)-1:0] expect_q [$];    // the commands taken, not done
    int                    cycle;
    int                    acks, dones;         // last beats' write answers given, dones
    integer                seed;
    bit                    seen_left, seen_src, seen_dst, seen_beat, seen_same, seen_overlap;
    bit                    seen_deep, seen_both, seen_burst, seen_block;

    DmaMover #(.ADDR_WIDTH(AW), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(IW),
               .DEPTH(DEPTH), .WR_ACK(WR_ACK), .MAX_BURST(MAX_BURST)) u_dma_mover(
        .clk, .rst_n, .cmd_valid, .cmd_ready, .cmd_id, .cmd_src, .cmd_dst, .cmd_n,
        .done_valid, .done_id, .done_n,
        .rd_req_valid, .rd_req_ready, .rd_req_addr, .rd_req_size, .rd_req_len, .rd_rsp_valid,
        .rd_rsp_data,
        .wr_req_valid, .wr_req_ready, .wr_req_addr, .wr_req_size, .wr_req_wdata, .wr_req_wstrb,
        .wr_req_rsp, .wr_rsp_valid);

    function automatic logic [DATA_WIDTH-1:0] beat_at(input logic [AW-1:0] a);
        logic [DATA_WIDTH-1:0] d;
        for (int k = 0; k < B; k++)
            d[8 * k +: 8] = mem[int'(a) + k];
        return d;
    endfunction

    // The bytes the transaction at s, d with left bytes moves, counted one by one: from two
    // beat starts while the source stays in its block (a burst), else while both stay in
    // their beats.
    function automatic int n_of(input int s, input int d, input int left);
        int k;
        k = 0;
        if (s % B == 0 && d % B == 0)
            while (k < left && (s + k) / BLOCK == s / BLOCK)
                k++;
        else
            while (k < left && (s + k) / B == s / B && (d + k) / B == d / B)
                k++;
        return k;
    endfunction

    initial begin
        int  len, s, d, left;           // the transfer being issued
        int  transfers;
        bit  taken;                     // the offered command is taken at the coming edge
        bit  offered;                   // a command was offered in the clock before
        logic [7:0] snap [MAX_LEN];
        done = 1'b0;
        seed = NAME;
        {seen_left, seen_src, seen_dst, seen_beat, seen_same, seen_overlap} = '0;
        {seen_deep, seen_both, seen_burst, seen_block} = '0;
        wbeats       = 0;
        cmd_valid    = 1'b0;
        cmd_id       = '0;
        cmd_src      = '0;
        cmd_dst      = '0;
        cmd_n        = '0;
        rd_req_ready = 1'b0;
        rd_rsp_valid = 1'b0;
        rd_rsp_data  = '0;
        wr_req_ready = 1'b0;
        wr_rsp_valid = 1'b0;
        cycle        = 0;
        acks         = 0;
        dones        = 0;
        transfers    = 0;
        left         = 0;
        s            = 0;
        d            = 0;
        taken        = 1'b0;
        offered      = 1'b0;
        for (int a = 0; a < MEM; a++) begin
            mem[a]     = 8'($random(seed));
            ref_mem[a] = mem[a];
        end
        @(posedge rst_n);
        forever begin
            @(negedge clk);
            cycle++;
            // The requester: the command taken at the edge before advances the transfer; a
            // new transfer once the last one is done.
            if (taken) begin
                xact_t x;
                x.id = cmd_id;
                x.n  = n_of(s, d, left);
                x.s  = s;
                x.d  = d;
                expect_q.push_back(x);
                beats_q.push_back((x.n - 1) / B + 1);
                s    += x.n;
                d    += x.n;
                left -= x.n;
            end
            if (left == 0 && expect_q.size() == 0 && transfers < N_TRANSFERS) begin
                bit aligned;
                len     = 1 + $unsigned($random(seed)) % MAX_LEN;
                s       = $unsigned($random(seed)) % (MEM - MAX_LEN);
                aligned = MAX_BURST > 1 && $random(seed) % 2 == 0;
                if (aligned)
                    s -= s % B;
                if (DEPTH == 1 && $random(seed) % 8 == 0) begin
                    d = s + $random(seed) % 12;                     // overlapping
                    if (d < 0 || d > MEM - MAX_LEN)
                        d = s;
                end else begin
                    do begin
                        d = $unsigned($random(seed)) % (MEM - MAX_LEN);
                        if (aligned)
                            d -= d % B;
                    end while (DEPTH > 1 && d < s + len && s < d + len);
                end
                if (d != s && (d - s < len && s - d < len))
                    seen_overlap = 1'b1;
                left = len;
                transfers++;
            end
            cmd_valid = left > 0;
            if (taken || !offered)          // a new offer gets a new ID; a waiting one keeps
                cmd_id = IW'($random(seed));
            offered   = cmd_valid;
            cmd_src   = AW'(s);
            cmd_dst   = AW'(d);
            cmd_n     = NW'(n_of(s, d, left));
            // The memory.
            rd_req_ready = $unsigned($random(seed)) % 10 < 7;
            wr_req_ready = $unsigned($random(seed)) % 10 < 7;
            rd_rsp_valid = ans.size() > 0 && ans_due[0] <= cycle;
            rd_rsp_data  = rd_rsp_valid ? ans[0] : '0;
            wr_rsp_valid = ack_due.size() > 0 && ack_due[0] <= cycle;
            #1;
            // Checks of this clock, then what the coming edge takes.
            if (done_valid) begin
                xact_t x;
                if (expect_q.size() == 0)
                    `DC_TEST_FAIL(model, $sformatf("DmaMover %0d: done without a command", NAME))
                x = expect_q.pop_front();
                dones++;
                if (WR_ACK != 0 && dones > acks)
                    `DC_TEST_FAIL(model, $sformatf(
                        "DmaMover %0d: done %0d before its write's answer", NAME, dones))
                if (done_id !== x.id || done_n !== NW'(x.n))
                    `DC_TEST_FAIL(model, $sformatf(
                        "DmaMover %0d: src %h dst %h: done %0d n %0d, expected %0d %0d", NAME,
                        x.s, x.d, done_id, done_n, x.id, x.n))
                for (int i = 0; i < x.n; i++)
                    snap[i] = ref_mem[x.s + i];
                for (int i = 0; i < x.n; i++)
                    ref_mem[x.d + i] = snap[i];
                if (x.n == B)                                     seen_beat = 1'b1;
                if (x.s % B == x.d % B && x.s % B != 0)           seen_same = 1'b1;
                if (x.n == BLOCK && MAX_BURST > 1)                seen_burst = 1'b1;
                if (x.n < B - ((x.s % B > x.d % B) ? x.s % B : x.d % B)) seen_left = 1'b1;
            end
            taken = cmd_valid && cmd_ready;
            if (taken) begin
                int k;
                k = n_of(s, d, left);
                if (k < left && s % B > d % B) seen_src = 1'b1;
                if (k < left && d % B > s % B) seen_dst = 1'b1;
                if (MAX_BURST > 1 && k < left && k > B && (s + k) % BLOCK == 0)
                    seen_block = 1'b1;
            end
            if (expect_q.size() + (taken ? 1 : 0) > DEPTH + 1)
                `DC_TEST_FAIL(model, $sformatf("DmaMover %0d: %0d in flight", NAME,
                                               expect_q.size() + (taken ? 1 : 0)))
            if (DEPTH > 1 && expect_q.size() >= DEPTH)
                seen_deep = 1'b1;
            if (rd_req_valid && rd_req_ready && wr_req_valid && wr_req_ready)
                seen_both = 1'b1;
            if (wr_req_rsp !== (WR_ACK != 0))
                `DC_TEST_FAIL(model, $sformatf("DmaMover %0d: wr_req_rsp %b", NAME, wr_req_rsp))
            if (rd_req_valid && rd_req_ready) begin
                int due;
                if (rd_req_addr[OW-1:0] != '0 || rd_req_size != 3'(OW) ||
                    int'(rd_req_len) != (n_of(s, d, left) - 1) / B)
                    `DC_TEST_FAIL(model, $sformatf("DmaMover %0d: read at %h size %0d len %0d",
                                                   NAME, rd_req_addr, rd_req_size, rd_req_len))
                due = cycle + 1 + $unsigned($random(seed)) % 4;
                for (int i = 0; i <= int'(rd_req_len); i++) begin
                    ans.push_back(beat_at(AW'(int'(rd_req_addr) + i * B)));
                    ans_due.push_back(due + i);
                end
            end
            if (wr_req_valid && wr_req_ready) begin
                if (wr_req_addr[OW-1:0] != '0 || wr_req_size != 3'(OW))
                    `DC_TEST_FAIL(model, $sformatf("DmaMover %0d: write at %h size %0d", NAME,
                                                   wr_req_addr, wr_req_size))
                for (int k = 0; k < B; k++)
                    if (wr_req_wstrb[k])
                        mem[int'(wr_req_addr) + k] = wr_req_wdata[8 * k +: 8];
                wbeats++;
                if (WR_ACK != 0) begin
                    ack_due.push_back(cycle + 1 + $unsigned($random(seed)) % 3);
                    ack_last.push_back(wbeats == beats_q[0]);
                end
                if (wbeats == beats_q[0]) begin
                    void'(beats_q.pop_front());
                    wbeats = 0;
                end
            end
            if (rd_rsp_valid) begin
                void'(ans.pop_front());
                void'(ans_due.pop_front());
            end
            if (wr_rsp_valid) begin
                void'(ack_due.pop_front());
                if (ack_last.pop_front())
                    acks++;
            end
            if (transfers == N_TRANSFERS && left == 0 && expect_q.size() == 0 && !taken)
                break;
            if (cycle > 200 * N_TRANSFERS)
                `DC_TEST_FAIL(model, $sformatf("DmaMover %0d: no end", NAME))
        end
        @(negedge clk);
        cmd_valid = 1'b0;
        repeat (8) @(negedge clk);
        for (int a = 0; a < MEM; a++)
            if (mem[a] !== ref_mem[a])
                `DC_TEST_FAIL(model, $sformatf("DmaMover %0d: byte %h is %h, expected %h", NAME,
                                               a, mem[a], ref_mem[a]))
        if (!seen_left || !seen_src || !seen_dst || !seen_beat || !seen_same ||
            (DEPTH == 1 && !seen_overlap) || (DEPTH > 1 && (!seen_deep || !seen_both)) ||
            (MAX_BURST > 1 && (!seen_burst || !seen_block)))
            `DC_TEST_FAIL(cover, $sformatf(
                {"DmaMover %0d: left %b src %b dst %b beat %b same %b overlap %b deep %b both %b",
                 " burst %b block %b"},
                NAME, seen_left, seen_src, seen_dst, seen_beat, seen_same, seen_overlap,
                seen_deep, seen_both, seen_burst, seen_block))
        done = 1'b1;
    end
endmodule

module TbDmaMover;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_32, done_64, done_128, done_32_4, done_64_8, done_32_4_b4, done_64_8_b8;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbDmaMoverCheck #(.DATA_WIDTH(32))  u_check_32(.clk, .rst_n, .done(done_32));
    TbDmaMoverCheck #(.DATA_WIDTH(64))  u_check_64(.clk, .rst_n, .done(done_64));
    TbDmaMoverCheck #(.DATA_WIDTH(128)) u_check_128(.clk, .rst_n, .done(done_128));
    TbDmaMoverCheck #(.DATA_WIDTH(32), .DEPTH(4), .WR_ACK(1)) u_check_32_4(
        .clk, .rst_n, .done(done_32_4));
    TbDmaMoverCheck #(.DATA_WIDTH(64), .DEPTH(8)) u_check_64_8(.clk, .rst_n, .done(done_64_8));
    TbDmaMoverCheck #(.DATA_WIDTH(32), .DEPTH(4), .WR_ACK(1), .MAX_BURST(4)) u_check_32_4_b4(
        .clk, .rst_n, .done(done_32_4_b4));
    TbDmaMoverCheck #(.DATA_WIDTH(64), .DEPTH(8), .MAX_BURST(8)) u_check_64_8_b8(
        .clk, .rst_n, .done(done_64_8_b8));

    initial begin
        wait (done_32 && done_64 && done_128 && done_32_4 && done_64_8 && done_32_4_b4 &&
              done_64_8_b8);
        $display("PASS");
        $finish;
    end
endmodule
