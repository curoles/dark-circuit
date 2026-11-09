/* Test of DmaMover, behave or struct version.
 *
 * The testbench is the requester (a DMA channel) and the memory. The requester runs random
 * transfers (source, destination, 1 to 80 bytes, sometimes overlapping), one transaction a
 * command: it offers the transfer's current addresses and bytes left with a random ID, waits
 * for done, checks done_id and done_n (the bytes counted one by one while both stay in their
 * beats, at most the bytes left), and advances. The memory is ready in 70 % of the clocks,
 * writes the strobed bytes at the clock it takes a write, and answers each read with its
 * beat as it was then, 1 to 4 clocks later. Model: a reference memory where each transaction
 * copies its n bytes from a snapshot of the source (the mover reads before it writes, so an
 * overlapping transaction copies the old bytes). At the end the memory equals the reference.
 * Beats of 32, 64 and 128 bits; 300 transfers each on Verilator, 60 on Icarus. Every case must
 * happen (checks named cover): a transaction cut by the bytes left, by the source's beat, by
 * the destination's beat, a whole beat, equal offsets that are not 0, an overlapping transfer.
 * Checks named model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbDmaMoverCheck #(
    parameter DATA_WIDTH = 64
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
    localparam LW      = 16;
    localparam IW      = 2;
    localparam B       = DATA_WIDTH / 8;        // bytes of a beat
    localparam OW      = $clog2(B);
    localparam MAX_LEN = 80;

    logic                  cmd_valid;
    wire                   cmd_ready;
    logic [IW-1:0]         cmd_id;
    logic [AW-1:0]         cmd_src, cmd_dst;
    logic [LW-1:0]         cmd_left;
    wire                   done_valid;
    wire  [IW-1:0]         done_id;
    wire  [OW:0]           done_n;
    wire                   mem_req_valid;
    logic                  mem_req_ready;
    wire                   mem_req_we;
    wire  [AW-1:0]         mem_req_addr;
    wire  [2:0]            mem_req_size;
    wire  [DATA_WIDTH-1:0] mem_req_wdata;
    wire  [B-1:0]          mem_req_wstrb;
    logic                  mem_rsp_valid;
    logic [DATA_WIDTH-1:0] mem_rsp_data;

    logic [7:0]            mem [MEM];           // the memory
    logic [7:0]            ref_mem [MEM];       // the reference
    logic [DATA_WIDTH-1:0] ans [$];             // answers due, in order
    int                    due [$];             // ... and their clocks
    int                    cycle;
    integer                seed;
    bit                    seen_left, seen_src, seen_dst, seen_beat, seen_same, seen_overlap;

    DmaMover #(.ADDR_WIDTH(AW), .DATA_WIDTH(DATA_WIDTH), .LEN_WIDTH(LW), .ID_WIDTH(IW))
        u_dma_mover(
            .clk, .rst_n, .cmd_valid, .cmd_ready, .cmd_id, .cmd_src, .cmd_dst, .cmd_left,
            .done_valid, .done_id, .done_n, .mem_req_valid, .mem_req_ready, .mem_req_we,
            .mem_req_addr, .mem_req_size, .mem_req_wdata, .mem_req_wstrb, .mem_rsp_valid,
            .mem_rsp_data);

    function automatic logic [DATA_WIDTH-1:0] beat_at(input logic [AW-1:0] a);
        logic [DATA_WIDTH-1:0] d;
        for (int k = 0; k < B; k++)
            d[8 * k +: 8] = mem[int'(a) + k];
        return d;
    endfunction

    // The memory: inputs at the falling edge; a request offered now is taken at the next
    // rising edge when ready, so its effect is applied here.
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
                if (mem_req_addr[OW-1:0] != '0 || mem_req_size != 3'(OW))
                    `DC_TEST_FAIL(model, $sformatf("DmaMover %0d: request at %h size %0d",
                                                   DATA_WIDTH, mem_req_addr, mem_req_size))
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

    // The requester.
    initial begin
        int len, s, d, n, left, k;
        logic [7:0] snap [MAX_LEN];
        done = 1'b0;
        seed = DATA_WIDTH;
        {seen_left, seen_src, seen_dst, seen_beat, seen_same, seen_overlap} = '0;
        cmd_valid = 1'b0;
        cmd_id    = '0;
        cmd_src   = '0;
        cmd_dst   = '0;
        cmd_left  = '0;
        for (int a = 0; a < MEM; a++) begin
            mem[a]     = 8'($random(seed));
            ref_mem[a] = mem[a];
        end
        @(posedge rst_n);
        repeat (N_TRANSFERS) begin
            len = 1 + $unsigned($random(seed)) % MAX_LEN;
            s   = $unsigned($random(seed)) % (MEM - MAX_LEN);
            d   = ($random(seed) % 8 == 0) ? s + $random(seed) % 12          // overlapping
                                            : $unsigned($random(seed)) % (MEM - MAX_LEN);
            if (d < 0 || d > MEM - MAX_LEN)
                d = s;
            if (d != s && (d - s < len && s - d < len))
                seen_overlap = 1'b1;
            left = len;
            while (left > 0) begin
                @(negedge clk);
                cmd_valid = 1'b1;
                cmd_id    = IW'($random(seed));
                cmd_src   = AW'(s);
                cmd_dst   = AW'(d);
                cmd_left  = LW'(left);
                while (!cmd_ready)
                    @(negedge clk);
                @(negedge clk);
                cmd_valid = 1'b0;
                while (!done_valid)
                    @(negedge clk);
                // n, counted one byte at a time.
                k = 0;
                while (k < left && (s + k) / B == s / B && (d + k) / B == d / B)
                    k++;
                if (done_id !== cmd_id || done_n !== (OW+1)'(k))
                    `DC_TEST_FAIL(model, $sformatf(
                        "DmaMover %0d: src %h dst %h left %0d: done %0d n %0d, expected %0d %0d",
                        DATA_WIDTH, s, d, left, done_id, done_n, cmd_id, k))
                n = k;
                if (n == left && n < B - ((s % B > d % B) ? s % B : d % B)) seen_left = 1'b1;
                if (n < left && s % B > d % B)                  seen_src  = 1'b1;
                if (n < left && d % B > s % B)                  seen_dst  = 1'b1;
                if (n == B)                                     seen_beat = 1'b1;
                if (s % B == d % B && s % B != 0)               seen_same = 1'b1;
                for (int i = 0; i < n; i++)
                    snap[i] = ref_mem[s + i];
                for (int i = 0; i < n; i++)
                    ref_mem[d + i] = snap[i];
                s    += n;
                d    += n;
                left -= n;
            end
        end
        repeat (8) @(negedge clk);
        for (int a = 0; a < MEM; a++)
            if (mem[a] !== ref_mem[a])
                `DC_TEST_FAIL(model, $sformatf("DmaMover %0d: byte %h is %h, expected %h",
                                               DATA_WIDTH, a, mem[a], ref_mem[a]))
        if (!seen_left || !seen_src || !seen_dst || !seen_beat || !seen_same || !seen_overlap)
            `DC_TEST_FAIL(cover, $sformatf(
                "DmaMover %0d: left %b src %b dst %b beat %b same %b overlap %b", DATA_WIDTH,
                seen_left, seen_src, seen_dst, seen_beat, seen_same, seen_overlap))
        done = 1'b1;
    end
endmodule

module TbDmaMover;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_32, done_64, done_128;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbDmaMoverCheck #(.DATA_WIDTH(32))  u_check_32(.clk, .rst_n, .done(done_32));
    TbDmaMoverCheck #(.DATA_WIDTH(64))  u_check_64(.clk, .rst_n, .done(done_64));
    TbDmaMoverCheck #(.DATA_WIDTH(128)) u_check_128(.clk, .rst_n, .done(done_128));

    initial begin
        wait (done_32 && done_64 && done_128);
        $display("PASS");
        $finish;
    end
endmodule
