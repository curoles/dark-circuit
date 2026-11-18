/* Test of Mig6's network on chip: four stand-in cores on the 2 x 2 meshes (Mig6Noc), each
 * through its PE's network interface, all to the shared memory at the north edge.
 *
 *   stand-in p --> Mig6PeNetIf (node p % 2, p / 2) --+
 *                                                    | Mig6Noc: request mesh, answer mesh
 *   shared memory: Mig6MemNetIf (node 1, 2) <--------+  --> AtomicUnit --> RAM
 *
 * Each stand-in core (TbMig6StandIn) has its own window of the shared memory (16 words at
 * 64 * p) and checks every answer there against its shadow memory: routes there and back,
 * credits, four PEs competing for one memory. Each also adds 1 to one shared counter
 * N_COUNTER times; the old counts the adds get back, over all PEs, must be 0, 1, ..., every
 * add's once (atomic under contention, the barrier's mechanism), and the counter must end at
 * the number of adds. The RAM answers after a random latency and is not always ready. Every
 * case must happen by the end: the stand-ins' (each opcode, req_ready low), Mig6MemNetIf
 * owing D answers. Checks before the end of a clock (the falling edge). Stops at the first
 * mismatch with $fatal; Mig6Noc stops at a flit out by a tied-off edge.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

module TbMig6NocCheck #(
    parameter BUF_DEPTH     = 4,        // routers' and network interfaces' buffers: credits
    parameter LINK_DELAY    = 1,        // clocks of a link between two routers
    parameter PENDING_WIDTH = 2,        // Mig6MemNetIf owes D = 1 << PENDING_WIDTH at most
    parameter N_REQS        = 2000,     // random requests per stand-in after its fixed start
    parameter N_COUNTER     = 50        // of them: adds to the shared counter, per stand-in
)(
    input  wire  clk,
    output logic done
);
    import Mig6NocPkg::*;
    import AtomicPkg::*;

    localparam RAM_AW       = 12;       // the RAM's byte address width
    localparam D            = 1 << PENDING_WIDTH;
    localparam WORDS        = 16;       // a stand-in's window
    localparam COUNTER_ADDR = 'h400;    // the shared counter, past the windows
    localparam N_ADDS       = N_PES * N_COUNTER;

    logic                          rst_n;
    req_link_fwd_t [N_PES-1:0]     pe_req_fwd;
    link_bwd_t     [N_PES-1:0]     pe_req_bwd;
    rsp_link_fwd_t [N_PES-1:0]     pe_rsp_fwd;
    link_bwd_t     [N_PES-1:0]     pe_rsp_bwd;
    req_link_fwd_t                 mem_req_fwd;
    link_bwd_t                     mem_req_bwd;
    rsp_link_fwd_t                 mem_rsp_fwd;
    link_bwd_t                     mem_rsp_bwd;
    logic          [N_PES-1:0]     merged;          // stand-in p's counts are in all_olds
    logic          [31:0]          all_olds [$];    // the old counts of every counter add
    // Mig6MemNetIf to AtomicUnit, AtomicUnit to the RAM
    logic                  au_valid;
    logic                  au_ready;
    logic                  au_we;
    logic [ADDR_WIDTH-1:0] au_addr;
    logic [SIZE_WIDTH-1:0] au_size;
    atop_t                 au_atop;
    logic [DATA_WIDTH-1:0] au_wdata;
    logic [STRB_WIDTH-1:0] au_wstrb;
    logic                  au_rsp_valid;
    logic [DATA_WIDTH-1:0] au_rsp_data;
    logic                  ram_valid;
    logic                  ram_ready;
    logic                  ram_we;
    // The RAM takes words with strobes in its window: the size and the address's other bits
    // are not read.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [ADDR_WIDTH-1:0] ram_addr;
    logic [SIZE_WIDTH-1:0] ram_size;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [DATA_WIDTH-1:0] ram_wdata;
    logic [STRB_WIDTH-1:0] ram_wstrb;
    logic                  ram_rsp_valid;
    logic [DATA_WIDTH-1:0] ram_rsp_data;

    SimRstGen #(.CYCLES(3)) u_sim_rst_gen(.clk, .rst_n);

    for (genvar p = 0; p < N_PES; p++) begin: g_pe
        logic                  req_valid;
        logic                  req_ready;
        logic                  req_we;
        logic [ADDR_WIDTH-1:0] req_addr;
        logic [SIZE_WIDTH-1:0] req_size;
        atop_t                 req_atop;
        CachePkg::cmo_t        req_cmo;
        logic [DATA_WIDTH-1:0] req_wdata;
        logic [STRB_WIDTH-1:0] req_wstrb;
        logic                  rsp_valid;
        logic [DATA_WIDTH-1:0] rsp_data;
        logic                  stand_in_done;

        TbMig6StandIn #(.ID(p), .SEED(1000 + 7 * p), .BASE(4 * WORDS * p), .WORDS(WORDS),
                        .N_REQS(N_REQS), .N_COUNTER(N_COUNTER),
                        .COUNTER_ADDR(COUNTER_ADDR)) u_stand_in(
            .clk, .rst_n,
            .req_valid, .req_ready, .req_we, .req_addr, .req_size, .req_atop, .req_cmo,
            .req_wdata, .req_wstrb, .rsp_valid, .rsp_data, .done(stand_in_done));

        Mig6PeNetIf #(.MY_PE_GRID_X(X_WIDTH'(p % MESH_X)), .MY_PE_GRID_Y(Y_WIDTH'(p / MESH_X)),
                      .BUF_DEPTH(BUF_DEPTH)) u_pe_net_if(
            .clk, .rst_n,
            .req_valid, .req_ready, .req_we, .req_addr, .req_size, .req_atop, .req_cmo,
            .req_wdata, .req_wstrb, .rsp_valid, .rsp_data,
            .noc_req_fwd(pe_req_fwd[p]), .noc_req_bwd(pe_req_bwd[p]),
            .noc_rsp_fwd(pe_rsp_fwd[p]), .noc_rsp_bwd(pe_rsp_bwd[p]));

        // When the stand-in is done, its counter adds' old counts join the others.
        initial begin
            merged[p] = 1'b0;
            wait (stand_in_done);
            foreach (u_stand_in.counter_olds[i]) all_olds.push_back(u_stand_in.counter_olds[i]);
            merged[p] = 1'b1;
        end
    end

    Mig6Noc #(.BUF_DEPTH(BUF_DEPTH), .LINK_DELAY(LINK_DELAY)) u_noc(
        .clk, .rst_n, .pe_req_fwd, .pe_req_bwd, .pe_rsp_fwd, .pe_rsp_bwd,
        .mem_req_fwd, .mem_req_bwd, .mem_rsp_fwd, .mem_rsp_bwd);

    Mig6MemNetIf #(.BUF_DEPTH(BUF_DEPTH), .PENDING_WIDTH(PENDING_WIDTH)) u_mem_net_if(
        .clk, .rst_n,
        .noc_req_fwd(mem_req_fwd), .noc_req_bwd(mem_req_bwd),
        .noc_rsp_fwd(mem_rsp_fwd), .noc_rsp_bwd(mem_rsp_bwd),
        .mem_req_valid(au_valid), .mem_req_ready(au_ready), .mem_req_we(au_we),
        .mem_req_addr(au_addr), .mem_req_size(au_size), .mem_req_atop(au_atop),
        .mem_req_wdata(au_wdata), .mem_req_wstrb(au_wstrb),
        .mem_rsp_valid(au_rsp_valid), .mem_rsp_data(au_rsp_data));

    AtomicUnit #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ATOM_WIDTH(DATA_WIDTH),
                 .PENDING_WIDTH(2)) u_atomic_unit(
        .clk, .rst_n,
        .req_valid(au_valid), .req_ready(au_ready), .req_we(au_we), .req_addr(au_addr),
        .req_size(au_size), .req_atop(au_atop), .req_wdata(au_wdata), .req_wstrb(au_wstrb),
        .rsp_valid(au_rsp_valid), .rsp_data(au_rsp_data),
        .mem_req_valid(ram_valid), .mem_req_ready(ram_ready), .mem_req_we(ram_we),
        .mem_req_addr(ram_addr), .mem_req_size(ram_size), .mem_req_wdata(ram_wdata),
        .mem_req_wstrb(ram_wstrb), .mem_rsp_valid(ram_rsp_valid),
        .mem_rsp_data(ram_rsp_data));

    // Not always ready; most reads fast, some slow. The counter starts at 0.
    SimLatencyRAM #(.DATA_SIZE(STRB_WIDTH), .ADDR_WIDTH(RAM_AW), .READY_PERCENT(80),
                    .FAST_PERCENT(70), .FAST_MIN(1), .FAST_MAX(2), .SLOW_MIN(4), .SLOW_MAX(12),
                    .MAX_PENDING(4)) u_ram(
        .clk, .rst_n,
        .req_valid(ram_valid), .req_ready(ram_ready), .req_we(ram_we),
        .req_addr({ram_addr[RAM_AW-1:2], 2'b00}), .req_wdata(ram_wdata),
        .req_wstrb(ram_wstrb), .rsp_valid(ram_rsp_valid), .rsp_data(ram_rsp_data));

    integer      n_owed_d;              // clocks with D answers owed
    integer      cycle;
    logic [31:0] count0;                // the counter before the first add
    logic [31:0] k;
    logic        seen [N_ADDS];         // an old count got back: count0 + its index

    initial begin
        done     = 1'b0;
        n_owed_d = 0;
        cycle    = 0;
        wait (rst_n);
        count0 = u_ram.read_word(RAM_AW'(COUNTER_ADDR));
        while (merged != '1) begin
            @(negedge clk);
            cycle = cycle + 1;
            if (u_mem_net_if.owed == (PENDING_WIDTH + 2)'(D)) n_owed_d = n_owed_d + 1;
        end
        // Every add's old count once: count0 .. count0 + N_ADDS - 1.
        for (int i = 0; i < N_ADDS; i++) seen[i] = 1'b0;
        if (all_olds.size() != N_ADDS)
            $fatal(1, "Mig6 NoC: %0d counter answers, expected %0d", all_olds.size(), N_ADDS);
        foreach (all_olds[i]) begin
            k = all_olds[i] - count0;
            if (k >= N_ADDS || seen[k])
                $fatal(1, "Mig6 NoC: counter answer %0d twice or out of range (start %0d)",
                       all_olds[i], count0);
            seen[k] = 1'b1;
        end
        if (u_ram.read_word(RAM_AW'(COUNTER_ADDR)) != count0 + N_ADDS)
            $fatal(1, "Mig6 NoC: the counter is %0d, expected %0d",
                   u_ram.read_word(RAM_AW'(COUNTER_ADDR)), count0 + N_ADDS);
        $display("Mig6 NoC: %0d clocks, %0d counter adds, clocks with D owed %0d", cycle,
                 N_ADDS, n_owed_d);
        if (n_owed_d == 0)
            $fatal(1, "Mig6 NoC: a case never happened (D owed is 0)");
        done = 1'b1;
    end
endmodule

module TbMig6Noc;
    wire clk;
    wire done;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbMig6NocCheck #(.BUF_DEPTH(4), .LINK_DELAY(1), .PENDING_WIDTH(2), .N_REQS(2000),
                     .N_COUNTER(50)) u_check(.clk, .done);

    initial begin
        wait (done);
        $display("PASS");
        $finish;
    end
endmodule
