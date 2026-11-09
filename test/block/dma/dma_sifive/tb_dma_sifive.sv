/* Test of DmaSifive, end to end, with the behave or the struct library.
 *
 * The testbench is software on the register port (a task per access, as Linux's sf-pdma
 * driver uses the registers) and the memory (ready in 70 % of the clocks, answers 1 to 4
 * clocks late). A program in phases:
 *  1. Next registers written, then claim: they read 0; NextConfig's wsize and rsize read the
 *     beat; a high word reads 0 (addresses and counts narrower than 32 bits).
 *  2. Every channel at once: a copy of 1 to 300 bytes, run with doneIE; each done interrupt
 *     comes; then Control (run 0, done 1, claim 1), ExecBytes 0, ExecDestination and
 *     ExecSource past the copy, ExecConfig; done cleared (the interrupt drops).
 *  3. A stop: a long copy, Control written 0 while it runs: run 0 but claim stays 1 (it
 *     clears only while run is 0); some clocks later ExecBytes stays above 0 and the bytes
 *     before it are copied; Control written 0 again: claim 0.
 *  4. repeat: done comes again and again with run kept 1 (done cleared each time with run
 *     written back, as Linux does); repeat lowered: the next done clears run.
 *  5. 0 bytes: done at once. 6. error and errorIE written by software: the error interrupt.
 * Copies never overlap, so the reference memory is a plain copy of the bytes moved. At the end
 * the memory equals it. Configurations: 4 channels with beats of 64 bits (the FU540's), 2 with
 * 32. Checks named model. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbDmaSifiveCheck #(
    parameter N_CHANNELS = 4,
    parameter DATA_WIDTH = 64
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done_all
);
    import DmaSifivePkg::*;

    localparam N     = N_CHANNELS;
    localparam AW    = 13;                          // a memory of 8 KiB
    localparam MEM   = 1 << AW;
    localparam LW    = 16;
    localparam RA    = CHAN_BITS + $clog2(N);       // bits of the register port's address
    localparam B     = DATA_WIDTH / 8;
    localparam LIMIT = 20000;

    logic                  req_valid;
    wire                   req_ready;
    logic                  req_we;
    logic [RA-1:0]         req_addr;
    logic [31:0]           req_wdata;
    logic [3:0]            req_wstrb;
    wire                   rsp_valid;
    wire  [31:0]           rsp_rdata;
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
    wire  [2*N-1:0]        irq;

    logic [7:0]            mem [MEM];
    logic [7:0]            ref_mem [MEM];
    logic [DATA_WIDTH-1:0] ans [$];
    int                    due [$];
    int                    cycle;
    integer                seed;
    logic [31:0]           v;

    DmaSifive #(.N_CHANNELS(N), .ADDR_WIDTH(AW), .DATA_WIDTH(DATA_WIDTH), .LEN_WIDTH(LW))
        u_dma_sifive(
            .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_addr, .req_wdata, .req_wstrb,
            .rsp_valid, .rsp_rdata, .mem_req_valid, .mem_req_ready, .mem_req_we,
            .mem_req_addr, .mem_req_size, .mem_req_wdata, .mem_req_wstrb, .mem_rsp_valid,
            .mem_rsp_data, .irq);

    function automatic logic [DATA_WIDTH-1:0] beat_at(input logic [AW-1:0] a);
        logic [DATA_WIDTH-1:0] d;
        for (int k = 0; k < B; k++)
            d[8 * k +: 8] = mem[int'(a) + k];
        return d;
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

    // One register access, as software does it.
    task automatic access(input logic we, input int addr, input logic [31:0] wdata,
                          output logic [31:0] rdata);
        @(negedge clk);
        req_valid = 1'b1;
        req_we    = we;
        req_addr  = RA'(addr);
        req_wdata = wdata;
        req_wstrb = 4'hf;
        @(posedge clk);
        while (!req_ready)
            @(posedge clk);
        @(negedge clk);
        req_valid = 1'b0;
        rdata     = rsp_rdata;
        if (!we && rsp_valid !== 1'b1)
            `DC_TEST_FAIL(model, $sformatf("DmaSifive %0d: no answer at %h", N, addr))
    endtask

    task automatic wr(input int c, input int off, input logic [31:0] data);
        logic [31:0] unused;
        access(1'b1, c * 'h1000 + off, data, unused);
    endtask

    task automatic rd(input int c, input int off, output logic [31:0] data);
        access(1'b0, c * 'h1000 + off, '0, data);
    endtask

    task automatic expect_reg(input int c, input int off, input logic [31:0] want,
                              input string what);
        logic [31:0] got;
        rd(c, off, got);
        if (got !== want)
            `DC_TEST_FAIL(model, $sformatf("DmaSifive %0d: channel %0d %s (%h): %h, expected %h",
                                           N, c, what, off, got, want))
    endtask

    function automatic logic [31:0] ctrl(input bit claim, input bit run, input bit die,
                                         input bit eie);
        logic [31:0] x;
        x              = '0;
        x[CLAIM_BIT]   = claim;
        x[RUN_BIT]     = run;
        x[DONE_IE_BIT] = die;
        x[ERR_IE_BIT]  = eie;
        return x;
    endfunction

    // NextConfig as read: repeat, and the beat in wsize and rsize.
    function automatic logic [31:0] config_of(input bit rep);
        logic [31:0] x;
        x                    = '0;
        x[REPEAT_BIT]        = rep;
        x[WSIZE_LSB +: 4]    = 4'($clog2(B));
        x[RSIZE_LSB +: 4]    = 4'($clog2(B));
        return x;
    endfunction

    task automatic setup(input int c, input int src, input int dst, input int len,
                           input bit rep);
        wr(c, NEXT_SRC, src);
        wr(c, NEXT_DST, dst);
        wr(c, NEXT_BYTES, len);
        wr(c, NEXT_CONFIG, rep ? (1 << REPEAT_BIT) : 0);
    endtask

    task automatic wait_irq(input int k);
        int n;
        n = 0;
        while (!irq[k]) begin
            @(negedge clk);
            n = n + 1;
            if (n > LIMIT)
                `DC_TEST_FAIL(model, $sformatf("DmaSifive %0d: no interrupt %0d", N, k))
        end
    endtask

    function automatic void copy(input int src, input int dst, input int len);
        for (int i = 0; i < len; i++)
            ref_mem[dst + i] = ref_mem[src + i];
    endfunction

    initial begin
        int src [N], dst [N], len [N];
        int moved;
        done_all  = 1'b0;
        seed      = 7 * N + DATA_WIDTH;
        req_valid = 1'b0;
        req_we    = 1'b0;
        req_addr  = '0;
        req_wdata = '0;
        req_wstrb = '0;
        for (int a = 0; a < MEM; a++) begin
            mem[a]     = 8'($random(seed));
            ref_mem[a] = mem[a];
        end
        @(posedge rst_n);

        // 1. A claim clears the Next registers.
        for (int c = 0; c < N; c++) begin
            setup(c, 'h123, 'h456, 77, 1'b1);
            expect_reg(c, NEXT_CONFIG, config_of(1'b1), "NextConfig");
            wr(c, CONTROL, ctrl(1, 0, 0, 0));
            expect_reg(c, NEXT_SRC, 0, "NextSource after claim");
            expect_reg(c, NEXT_BYTES, 0, "NextBytes after claim");
            expect_reg(c, NEXT_CONFIG, config_of(1'b0), "NextConfig after claim");
            expect_reg(c, NEXT_DST + 4, 0, "NextDestination high");
        end

        // 2. Every channel at once.
        for (int c = 0; c < N; c++) begin
            len[c] = 1 + $unsigned($random(seed)) % 300;
            src[c] = c * 1024 + $unsigned($random(seed)) % (1024 - 300);
            dst[c] = 4096 + c * 1024 + $unsigned($random(seed)) % (1024 - 300);
            setup(c, src[c], dst[c], len[c], 1'b0);
        end
        for (int c = 0; c < N; c++)
            wr(c, CONTROL, ctrl(1, 1, 1, 0));
        for (int c = 0; c < N; c++) begin
            wait_irq(2 * c);
            v = ctrl(1, 0, 1, 0);
            v[DONE_BIT] = 1'b1;
            expect_reg(c, CONTROL, v, "Control after the copy");
            expect_reg(c, EXEC_BYTES, 0, "ExecBytes");
            expect_reg(c, EXEC_DST, dst[c] + len[c], "ExecDestination");
            expect_reg(c, EXEC_SRC, src[c] + len[c], "ExecSource");
            expect_reg(c, EXEC_CONFIG, config_of(1'b0), "ExecConfig");
            wr(c, CONTROL, ctrl(1, 0, 1, 0));               // done cleared
            @(negedge clk);
            if (irq[2 * c] !== 1'b0)
                `DC_TEST_FAIL(model, $sformatf("DmaSifive %0d: done interrupt after clear", N))
            copy(src[c], dst[c], len[c]);
        end

        // 3. A stop.
        setup(0, 'h100, 4096 + 'h100, 600, 1'b0);
        wr(0, CONTROL, ctrl(1, 1, 0, 0));
        repeat (40) @(negedge clk);
        wr(0, CONTROL, 0);
        expect_reg(0, CONTROL, ctrl(1, 0, 0, 0), "Control after a stop");
        repeat (200) @(negedge clk);
        rd(0, EXEC_BYTES, v);
        if (v == 0 || v >= 600)
            `DC_TEST_FAIL(model, $sformatf("DmaSifive %0d: ExecBytes %0d after a stop", N, v))
        moved = 600 - int'(v);
        repeat (200) @(negedge clk);
        expect_reg(0, EXEC_BYTES, v, "ExecBytes, stopped");
        expect_reg(0, EXEC_SRC, 'h100 + moved, "ExecSource, stopped");
        copy('h100, 4096 + 'h100, moved);
        wr(0, CONTROL, 0);
        expect_reg(0, CONTROL, 0, "Control, released");

        // 4. repeat.
        wr(N - 1, CONTROL, ctrl(1, 0, 0, 0));
        setup(N - 1, 'h40 + (N - 1) * 1024, 4096 + 'h40 + (N - 1) * 1024, 37, 1'b1);
        wr(N - 1, CONTROL, ctrl(1, 1, 1, 0));
        repeat (2) begin
            wait_irq(2 * (N - 1));
            v = ctrl(1, 1, 1, 0);
            v[DONE_BIT] = 1'b1;
            expect_reg(N - 1, CONTROL, v, "Control, repeating");
            wr(N - 1, CONTROL, ctrl(1, 1, 1, 0));           // done cleared, run written back
        end
        wr(N - 1, NEXT_CONFIG, 0);
        wait_irq(2 * (N - 1));
        rd(N - 1, CONTROL, v);
        if (v[RUN_BIT] !== 1'b0)
            `DC_TEST_FAIL(model, $sformatf("DmaSifive %0d: run after repeat lowered", N))
        wr(N - 1, CONTROL, ctrl(1, 0, 0, 0));
        copy('h40 + (N - 1) * 1024, 4096 + 'h40 + (N - 1) * 1024, 37);

        // 5. 0 bytes; 6. the error interrupt.
        setup(0, 0, 4096, 0, 1'b0);
        wr(0, CONTROL, ctrl(1, 1, 1, 0));
        wait_irq(0);
        expect_reg(0, CONTROL, ctrl(1, 0, 1, 0) | (1 << DONE_BIT), "Control, 0 bytes");
        wr(0, CONTROL, ctrl(1, 0, 0, 1) | (1 << ERR_BIT));
        @(negedge clk);
        if (irq[1] !== 1'b1)
            `DC_TEST_FAIL(model, $sformatf("DmaSifive %0d: no error interrupt", N))
        wr(0, CONTROL, ctrl(1, 0, 0, 1));
        @(negedge clk);
        if (irq !== '0)
            `DC_TEST_FAIL(model, $sformatf("DmaSifive %0d: interrupts %b at the end", N, irq))

        repeat (8) @(negedge clk);
        for (int a = 0; a < MEM; a++)
            if (mem[a] !== ref_mem[a])
                `DC_TEST_FAIL(model, $sformatf("DmaSifive %0d: byte %h is %h, expected %h", N,
                                               a, mem[a], ref_mem[a]))
        done_all = 1'b1;
    end
endmodule

module TbDmaSifive;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_4, done_2;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbDmaSifiveCheck #(.N_CHANNELS(4), .DATA_WIDTH(64)) u_check_4(.clk, .rst_n, .done_all(done_4));
    TbDmaSifiveCheck #(.N_CHANNELS(2), .DATA_WIDTH(32)) u_check_2(.clk, .rst_n, .done_all(done_2));

    initial begin
        wait (done_4 && done_2);
        $display("PASS");
        $finish;
    end
endmodule
