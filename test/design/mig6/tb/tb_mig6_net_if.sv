/* Test of Mig6's two network interfaces, joined without a mesh: a stand-in core sends
 * requests through Mig6PeNetIf, Mig6MemNetIf takes them to AtomicUnit and a RAM, the
 * answers come back.
 *
 *   stand-in core --> Mig6PeNetIf ==request link==> Mig6MemNetIf --> AtomicUnit --> RAM
 *   (TbMig6StandIn) <-- Mig6PeNetIf <==answer link=== throttle <== Mig6MemNetIf
 *
 * The stand-in core (TbMig6StandIn) sends a fixed start, then random reads, writes, atomics,
 * CBOs, LRs, SCs and burst reads (up to 16 words, so longer than D) in its window, and
 * checks every answer against its shadow memory and
 * every SC's status against its model of the reservation; and LR/SC increments of a word of
 * its own (alone: none fails). The RAM
 * answers after a random latency and is not always ready. The throttle on the answer link
 * holds answers back at random (a busy mesh): without it Mig6PeNetIf would take every
 * answer at once and Mig6MemNetIf would never wait for a credit. Every case must happen by
 * the end: the stand-in's (each opcode, an SC that succeeds and one that fails, req_ready
 * low, a burst), Mig6MemNetIf owing D answers, an answer waiting for a credit, an SC waiting
 * for the answers in the memory, a burst's word held at the gate (owed D in a burst), a
 * burst's answer paused inside its packet (a body flit waiting for a credit). Checks before
 * the end of a clock (the falling edge), drives
 * after its rising edge. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

module TbMig6NetIfCheck #(
    parameter BUF_DEPTH     = 4,        // the links' buffers: credits
    parameter PENDING_WIDTH = 2,        // Mig6MemNetIf owes D = 1 << PENDING_WIDTH at most
    parameter THROTTLE_PCT  = 25,       // clocks in which the throttle passes an answer on
    parameter N_REQS        = 3000      // random requests after the fixed start
)(
    input  wire  clk,
    output logic done
);
    import Mig6NocPkg::*;
    import AtomicPkg::*;

    localparam RAM_AW = 12;             // the RAM's byte address width
    localparam D      = 1 << PENDING_WIDTH;

    logic                  rst_n;
    // The stand-in core's request channel
    logic                  req_valid;
    logic                  req_ready;
    logic                  req_we;
    logic [ADDR_WIDTH-1:0] req_addr;
    logic [SIZE_WIDTH-1:0] req_size;
    atop_t                 req_atop;
    CachePkg::cmo_t        req_cmo;
    logic                  req_excl;
    logic [LEN_WIDTH-1:0]  req_len;
    logic                  req_rsp;
    logic [DATA_WIDTH-1:0] req_wdata;
    logic [STRB_WIDTH-1:0] req_wstrb;
    logic                  rsp_valid;
    logic [DATA_WIDTH-1:0] rsp_data;
    logic                  stand_in_done;
    // The links
    req_link_fwd_t         req_fwd;
    link_bwd_t             req_bwd;
    rsp_link_fwd_t         mem_rsp_fwd;     // Mig6MemNetIf to the throttle
    link_bwd_t             mem_rsp_bwd;
    rsp_link_fwd_t         pe_rsp_fwd;      // the throttle to Mig6PeNetIf
    // A credit's vc is not read: one VC.
    /* verilator lint_off UNUSEDSIGNAL */
    link_bwd_t             pe_rsp_bwd;
    /* verilator lint_on UNUSEDSIGNAL */
    // Mig6MemNetIf to AtomicUnit, AtomicUnit to the RAM
    logic                  au_valid;
    logic                  au_ready;
    logic                  au_we;
    logic                  au_rsp;
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
    // The RAM answers reads only: no write that wants an answer reaches it.
    /* verilator lint_off UNUSEDSIGNAL */
    logic                  ram_rsp;
    /* verilator lint_on UNUSEDSIGNAL */
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

    TbMig6StandIn #(.ID(0), .SEED(12345), .BASE(0), .WORDS(16), .N_REQS(N_REQS),
                    .N_LRSC(20), .LRSC_ADDR('h100)) u_stand_in(
        .clk, .rst_n,
        .req_valid, .req_ready, .req_we, .req_addr, .req_size, .req_atop, .req_cmo,
        .req_excl, .req_len, .req_rsp, .req_wdata, .req_wstrb, .rsp_valid, .rsp_data,
        .done(stand_in_done));

    Mig6PeNetIf #(.MY_PE_GRID_X(2'd1), .MY_PE_GRID_Y(2'd0), .BUF_DEPTH(BUF_DEPTH)) u_pe_net_if(
        .clk, .rst_n,
        .req_valid, .req_ready, .req_we, .req_addr, .req_size, .req_atop, .req_cmo,
        .req_excl, .req_len, .req_rsp, .req_wdata, .req_wstrb, .rsp_valid, .rsp_data,
        .noc_req_fwd(req_fwd), .noc_req_bwd(req_bwd),
        .noc_rsp_fwd(pe_rsp_fwd), .noc_rsp_bwd(pe_rsp_bwd));

    Mig6MemNetIf #(.BUF_DEPTH(BUF_DEPTH), .PENDING_WIDTH(PENDING_WIDTH)) u_mem_net_if(
        .clk, .rst_n,
        .noc_req_fwd(req_fwd), .noc_req_bwd(req_bwd),
        .noc_rsp_fwd(mem_rsp_fwd), .noc_rsp_bwd(mem_rsp_bwd),
        .mem_req_valid(au_valid), .mem_req_ready(au_ready), .mem_req_we(au_we),
        .mem_req_rsp(au_rsp), .mem_req_addr(au_addr), .mem_req_size(au_size),
        .mem_req_atop(au_atop),
        .mem_req_wdata(au_wdata), .mem_req_wstrb(au_wstrb),
        .mem_rsp_valid(au_rsp_valid), .mem_rsp_data(au_rsp_data));

    AtomicUnit #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ATOM_WIDTH(DATA_WIDTH),
                 .PENDING_WIDTH(2)) u_atomic_unit(
        .clk, .rst_n,
        .req_valid(au_valid), .req_ready(au_ready), .req_we(au_we), .req_rsp(au_rsp),
        .req_addr(au_addr), .req_size(au_size), .req_atop(au_atop), .req_wdata(au_wdata),
        .req_wstrb(au_wstrb), .rsp_valid(au_rsp_valid), .rsp_data(au_rsp_data),
        .mem_req_valid(ram_valid), .mem_req_ready(ram_ready), .mem_req_we(ram_we),
        .mem_req_rsp(ram_rsp), .mem_req_addr(ram_addr), .mem_req_size(ram_size),
        .mem_req_wdata(ram_wdata),
        .mem_req_wstrb(ram_wstrb), .mem_rsp_valid(ram_rsp_valid),
        .mem_rsp_data(ram_rsp_data));

    // Not always ready; most reads fast, some slow.
    SimLatencyRAM #(.DATA_SIZE(STRB_WIDTH), .ADDR_WIDTH(RAM_AW), .READY_PERCENT(80),
                    .FAST_PERCENT(70), .FAST_MIN(1), .FAST_MAX(2), .SLOW_MIN(4), .SLOW_MAX(12),
                    .MAX_PENDING(4)) u_ram(
        .clk, .rst_n,
        .req_valid(ram_valid), .req_ready(ram_ready), .req_we(ram_we),
        .req_addr({ram_addr[RAM_AW-1:2], 2'b00}), .req_wdata(ram_wdata),
        .req_wstrb(ram_wstrb), .rsp_valid(ram_rsp_valid), .rsp_data(ram_rsp_data));

    rsp_flit_t thr_q [$];               // the throttle's flits
    integer    thr_credits;             // Mig6PeNetIf's free slots, as the throttle sees them
    integer    seed;
    integer    n_owed_d;                // clocks with D answers owed
    integer    n_rsp_wait;              // clocks with an answer waiting for a credit
    integer    n_sc_wait;               // clocks with an SC waiting for answers in memory
    integer    n_gated;                 // clocks with a burst's word held at the gate
    integer    n_body_wait;             // clocks with a body flit waiting for a credit

    // The throttle, and the counts of Mig6MemNetIf's cases, until the stand-in is done.
    initial begin
        done        = 1'b0;
        pe_rsp_fwd  = '0;
        mem_rsp_bwd = '0;
        seed        = 777;
        n_owed_d    = 0;
        n_rsp_wait  = 0;
        n_sc_wait   = 0;
        n_gated     = 0;
        n_body_wait = 0;
        thr_credits = BUF_DEPTH;
        wait (rst_n);
        while (!stand_in_done) begin
            @(negedge clk);
            if (u_mem_net_if.owed == (PENDING_WIDTH + 2)'(D)) n_owed_d = n_owed_d + 1;
            if (!u_mem_net_if.rsp_empty && u_mem_net_if.credits_q == '0)
                n_rsp_wait = n_rsp_wait + 1;
            if (u_mem_net_if.whole && u_mem_net_if.cur.op == REQ_SC && !u_mem_net_if.src_empty)
                n_sc_wait = n_sc_wait + 1;
            if (u_mem_net_if.beat_valid && !u_mem_net_if.gate && !u_mem_net_if.split_ready)
                n_gated = n_gated + 1;
            if (!u_mem_net_if.rsp_empty && !u_mem_net_if.out_front.head &&
                u_mem_net_if.credits_q == '0)
                n_body_wait = n_body_wait + 1;
            if (mem_rsp_fwd.valid) begin
                if (thr_q.size() >= BUF_DEPTH)
                    $fatal(1, "Mig6 NetIf: Mig6MemNetIf sent without a credit");
                thr_q.push_back(mem_rsp_fwd.flit);
            end
            if (pe_rsp_fwd.valid) begin
                void'(thr_q.pop_front());
                thr_credits = thr_credits - 1;
            end
            if (pe_rsp_bwd.valid) thr_credits = thr_credits + 1;
            @(posedge clk);
            #1;
            mem_rsp_bwd = '0;
            pe_rsp_fwd  = '0;
            if (thr_q.size() > 0 && thr_credits > 0 && {$random(seed)} % 100 < THROTTLE_PCT)
            begin
                pe_rsp_fwd.valid  = 1'b1;
                pe_rsp_fwd.flit   = thr_q[0];
                mem_rsp_bwd.valid = 1'b1;       // its slot frees as it leaves
            end
        end
        $display("Mig6 NetIf: clocks with D owed %0d, an answer waiting %0d, an SC waiting %0d",
                 n_owed_d, n_rsp_wait, n_sc_wait);
        $display("Mig6 NetIf: clocks with a burst's word at the gate %0d, a body flit waiting %0d",
                 n_gated, n_body_wait);
        if (n_owed_d == 0 || n_rsp_wait == 0 || n_sc_wait == 0 || n_gated == 0 ||
            n_body_wait == 0)
            $fatal(1, "Mig6 NetIf: a case never happened (a count above is 0)");
        done = 1'b1;
    end
endmodule

module TbMig6NetIf;
    wire clk;
    wire done;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbMig6NetIfCheck #(.BUF_DEPTH(4), .PENDING_WIDTH(2), .THROTTLE_PCT(25), .N_REQS(3000))
        u_check(.clk, .done);

    initial begin
        wait (done);
        $display("PASS");
        $finish;
    end
endmodule
