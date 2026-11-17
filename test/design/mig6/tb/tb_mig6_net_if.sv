/* Test of Mig6's two network interfaces, joined without a mesh: a stand-in core sends
 * requests through Mig6PeNetIf, Mig6MemNetIf takes them to AtomicUnit and a RAM, the
 * answers come back.
 *
 *   stand-in core --> Mig6PeNetIf ==request link==> Mig6MemNetIf --> AtomicUnit --> RAM
 *   (this test)   <-- Mig6PeNetIf <==answer link=== throttle <== Mig6MemNetIf
 *
 * The stand-in core is the requester of the library request channel: first a fixed start
 * (every word of the RAM's window written, two read back, an atomic), then random requests:
 * reads, writes and atomics of the nine operations on a window of WORDS words, bytes,
 * halfwords and words with their strobes, CBOs, with random gaps; an offer stays the same
 * until taken. A shadow memory, updated in the order the requests are taken (one requester:
 * the order of the memory), gives each read's and atomic's answer, which the test computes
 * itself; every answer must be the oldest expected one. The RAM answers after a random
 * latency and is not always ready. The throttle on the answer link holds answers back at
 * random (a busy mesh): without it Mig6PeNetIf would take every answer at once and
 * Mig6MemNetIf would never wait for a credit. Every case must happen by the end: each
 * opcode, Mig6MemNetIf owing D answers, an answer waiting for a credit, a request
 * Mig6PeNetIf did not take (req_ready low). Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

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

    localparam WORDS      = 16;         // the window: words 0 .. WORDS - 1 of the RAM
    localparam RAM_AW     = 12;         // the RAM's byte address width
    localparam D          = 1 << PENDING_WIDTH;
    localparam N_FIXED    = WORDS + 3;  // the fixed start: writes, two reads, an atomic
    localparam MAX_CYCLES = 200000;

    logic                  rst_n;
    // The stand-in core's request channel
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

    Mig6PeNetIf #(.MY_X(2'd1), .MY_Y(2'd0), .BUF_DEPTH(BUF_DEPTH)) u_pe_net_if(
        .clk, .rst_n,
        .req_valid, .req_ready, .req_we, .req_addr, .req_size, .req_atop, .req_cmo,
        .req_wdata, .req_wstrb, .rsp_valid, .rsp_data,
        .noc_req_fwd(req_fwd), .noc_req_bwd(req_bwd),
        .noc_rsp_fwd(pe_rsp_fwd), .noc_rsp_bwd(pe_rsp_bwd));

    Mig6MemNetIf #(.BUF_DEPTH(BUF_DEPTH), .PENDING_WIDTH(PENDING_WIDTH)) u_mem_net_if(
        .clk, .rst_n,
        .noc_req_fwd(req_fwd), .noc_req_bwd(req_bwd),
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

    // Not always ready; most reads fast, some slow.
    SimLatencyRAM #(.DATA_SIZE(STRB_WIDTH), .ADDR_WIDTH(RAM_AW), .READY_PERCENT(80),
                    .FAST_PERCENT(70), .FAST_MIN(1), .FAST_MAX(2), .SLOW_MIN(4), .SLOW_MAX(12),
                    .MAX_PENDING(4)) u_ram(
        .clk, .rst_n,
        .req_valid(ram_valid), .req_ready(ram_ready), .req_we(ram_we),
        .req_addr({ram_addr[RAM_AW-1:2], 2'b00}), .req_wdata(ram_wdata),
        .req_wstrb(ram_wstrb), .rsp_valid(ram_rsp_valid), .rsp_data(ram_rsp_data));

    // The atomic operations, computed here (AtomicUnit uses Alu2): op(old, operand).
    localparam atop_t ATOPS [9] = '{ATOP_LD_ADD, ATOP_LD_CLR, ATOP_LD_EOR, ATOP_LD_SET,
                                    ATOP_LD_SMAX, ATOP_LD_SMIN, ATOP_LD_UMAX, ATOP_LD_UMIN,
                                    ATOP_SWAP};

    function automatic logic [31:0] amo(atop_t op, logic [31:0] old, logic [31:0] x);
        case (op)
            ATOP_LD_ADD:  return old + x;
            ATOP_LD_CLR:  return old & ~x;
            ATOP_LD_EOR:  return old ^ x;
            ATOP_LD_SET:  return old | x;
            ATOP_LD_SMAX: return ($signed(old) > $signed(x)) ? old : x;
            ATOP_LD_SMIN: return ($signed(old) < $signed(x)) ? old : x;
            ATOP_LD_UMAX: return (old > x) ? old : x;
            ATOP_LD_UMIN: return (old < x) ? old : x;
            default:      return x;     // ATOP_SWAP
        endcase
    endfunction

    // The shadow memory, the expected answers, the throttle's flits.
    logic [31:0]   shadow [WORDS];
    logic [31:0]   expect_q [$];
    rsp_flit_t     thr_q [$];
    integer        thr_credits;     // Mig6PeNetIf's free slots, as the throttle sees them
    integer        seed;
    integer        cycle;
    integer        n_sent;          // requests taken
    integer        n_op [8];        // per opcode, by its value
    integer        n_owed_d;        // clocks with D answers owed
    integer        n_rsp_wait;      // clocks with an answer waiting for a credit
    integer        n_not_ready;     // clocks with an offer Mig6PeNetIf did not take
    integer        r;
    logic          taken;           // the offer is taken at the next rising edge
    req_op_e       op;
    logic [31:0]   old;
    logic [$clog2(WORDS)-1:0] w;    // the word of a request in the window

    // A request offered by the stand-in core: the fixed start, then random ones.
    task automatic offer(input integer k);
        integer      word;
        integer      kind;
        integer      off;
        logic [31:0] data;

        data      = $random(seed);
        word      = {$random(seed)} % WORDS;
        req_we    = 1'b0;
        req_atop  = ATOP_NONE;
        req_cmo   = CachePkg::CMO_NONE;
        req_wdata = data;
        req_wstrb = '0;
        req_size  = SIZE_WIDTH'(2);
        if (k < WORDS) begin                    // fixed: write word k
            word      = k;
            req_we    = 1'b1;
            req_wstrb = '1;
        end else if (k < WORDS + 2) begin       // fixed: read words 0 and WORDS - 1
            word = (k == WORDS) ? 0 : WORDS - 1;
        end else if (k == WORDS + 2) begin      // fixed: an atomic add on word 1
            word     = 1;
            req_atop = ATOP_LD_ADD;
        end else begin
            kind = {$random(seed)} % 20;
            if (kind < 6) begin                 // a read
                req_size = SIZE_WIDTH'({$random(seed)} % 3);
            end else if (kind < 12) begin       // a write of a byte, a halfword or a word
                req_we   = 1'b1;
                req_size = SIZE_WIDTH'({$random(seed)} % 3);
                off      = (req_size == 0) ? {$random(seed)} % 4
                         : (req_size == 1) ? 2 * ({$random(seed)} % 2) : 0;
                req_wstrb = (req_size == 0) ? 4'b0001 << off
                          : (req_size == 1) ? 4'b0011 << off : 4'b1111;
            end else if (kind < 19) begin       // an atomic
                req_atop = ATOPS[{$random(seed)} % 9];
            end else begin                      // a CBO, a write without strobes
                req_we  = 1'b1;
                req_cmo = CachePkg::cmo_t'(1 + {$random(seed)} % 3);
            end
        end
        off = 0;
        if (req_we && req_cmo == CachePkg::CMO_NONE)
            for (int b = 0; b < 4; b++)
                if (req_wstrb[b]) begin
                    off = b;
                    break;
                end
        if (!req_we && req_size == 0) off = {$random(seed)} % 4;
        if (!req_we && req_size == 1) off = 2 * ({$random(seed)} % 2);
        req_addr  = ADDR_WIDTH'(4 * word + off);
        req_valid = 1'b1;
    endtask

    initial begin
        done        = 1'b0;
        req_valid   = 1'b0;
        pe_rsp_fwd  = '0;
        mem_rsp_bwd = '0;
        seed        = 12345;
        cycle       = 0;
        n_sent      = 0;
        n_owed_d    = 0;
        n_rsp_wait  = 0;
        n_not_ready = 0;
        thr_credits = BUF_DEPTH;
        for (int i = 0; i < 8; i++) n_op[i] = 0;
        wait (rst_n);
        while (!(n_sent == N_FIXED + N_REQS && expect_q.size() == 0 && !req_valid)) begin
            // Check this clock before its end (the falling edge): what happens at the next
            // rising edge.
            @(negedge clk);
            taken = req_valid && req_ready;
            cycle = cycle + 1;
            if (cycle > MAX_CYCLES)
                $fatal(1, "Mig6 NetIf: no end after %0d clocks: %0d taken, %0d answers owed",
                       MAX_CYCLES, n_sent, expect_q.size());
            if (req_valid && !req_ready) n_not_ready = n_not_ready + 1;
            if (u_mem_net_if.owed == (PENDING_WIDTH + 2)'(D)) n_owed_d = n_owed_d + 1;
            if (!u_mem_net_if.rsp_empty && u_mem_net_if.credits_q == '0)
                n_rsp_wait = n_rsp_wait + 1;
            if (rsp_valid) begin
                if (expect_q.size() == 0)
                    $fatal(1, "Mig6 NetIf: an answer %h, none expected", rsp_data);
                if (rsp_data !== expect_q[0])
                    $fatal(1, "Mig6 NetIf: answer %h, expected %h", rsp_data, expect_q[0]);
                void'(expect_q.pop_front());
            end
            if (taken) begin                    // the shadow memory, the expected answer
                w  = req_addr[$clog2(WORDS)+1:2];
                op = (req_cmo != CachePkg::CMO_NONE) ? REQ_CBO
                   : (req_atop != ATOP_NONE) ? REQ_ATOMIC : req_we ? REQ_WRITE : REQ_READ;
                n_op[op] = n_op[op] + 1;
                case (op)
                    REQ_READ:
                        expect_q.push_back(shadow[w]);
                    REQ_WRITE:
                        for (int b = 0; b < 4; b++)
                            if (req_wstrb[b]) shadow[w][8*b +: 8] = req_wdata[8*b +: 8];
                    REQ_ATOMIC: begin
                        old = shadow[w];
                        expect_q.push_back(old);
                        shadow[w] = amo(req_atop, old, req_wdata);
                    end
                    default: ;                  // REQ_CBO: nothing changes
                endcase
                n_sent = n_sent + 1;
            end
            // The throttle: a flit from Mig6MemNetIf, one passed on, credits back.
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
            // Drive the next clock, after its rising edge.
            @(posedge clk);
            #1;
            if (taken) req_valid = 1'b0;
            mem_rsp_bwd = '0;
            pe_rsp_fwd  = '0;
            r = {$random(seed)} % 100;
            if (thr_q.size() > 0 && thr_credits > 0 && r < THROTTLE_PCT) begin
                pe_rsp_fwd.valid = 1'b1;
                pe_rsp_fwd.flit  = thr_q[0];
                mem_rsp_bwd.valid = 1'b1;       // its slot frees as it leaves
            end
            if (!req_valid && n_sent < N_FIXED + N_REQS
                && (n_sent < N_FIXED || {$random(seed)} % 4 != 0))
                offer(n_sent);
        end
        $display("Mig6 NetIf: %0d requests in %0d clocks: read %0d write %0d atomic %0d cbo %0d",
                 n_sent, cycle, n_op[REQ_READ], n_op[REQ_WRITE], n_op[REQ_ATOMIC],
                 n_op[REQ_CBO]);
        $display("Mig6 NetIf: clocks with D owed %0d, an answer waiting %0d, not ready %0d",
                 n_owed_d, n_rsp_wait, n_not_ready);
        if (n_op[REQ_READ] == 0 || n_op[REQ_WRITE] == 0 || n_op[REQ_ATOMIC] == 0
            || n_op[REQ_CBO] == 0 || n_owed_d == 0 || n_rsp_wait == 0 || n_not_ready == 0)
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
