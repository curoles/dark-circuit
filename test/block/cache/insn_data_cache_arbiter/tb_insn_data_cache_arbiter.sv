/* Test of InsnDataCacheArbiter.
 *
 * Every arbiter has an environment of its own: an instruction-cache model (reads), a
 * data-cache model (reads and writes) and a memory model. The cache models keep a request
 * until it is taken (valid/ready), may have several reads in memory and check every answer:
 * it is theirs (the oldest read they wait for) and its line is the line of its address. The
 * size of a request (here the low 3 bits of its address) must come to memory with it, and
 * the atop of a data read (here bits 8..3 of its address; a write's and an instruction
 * read's ATOP_NONE).
 * Memory takes requests when ready (random) and answers reads in order, 1 to 6 clocks after
 * taking them; prio is random. The model has the arbiter's two flow-through buffers: a
 * cache's request is taken when its buffer is empty and goes on from there (in the same
 * clock when memory takes it, else from the buffer). Checks in every clock, before the
 * rising edge:
 * - a cache's ready is exactly "its buffer is empty", and it does not move when the other
 *   side's valid or memory's ready changes within the clock (the cut, check_cut);
 * - memory gets the request of the side the arbiter presents: the held one, else prio's or
 *   POLICY's when both may go (round-robin: not the side taken last), else the one that
 *   may go (a read only with fewer than 1 << PENDING_WIDTH reads in memory);
 * - a request presented and not taken is still presented, unchanged;
 * - an answer goes to the side of the oldest read in memory, and only then.
 * Runs with POLICY round-robin (PENDING_WIDTH 1), data first (1) and instruction first (2);
 * 20000 clocks on Verilator, 2000 on Icarus. In the end every case must have happened: ties
 * decided by each prio and by POLICY, a held request, a full queue that stops a read while a
 * write goes, answers to both sides, a request that flowed through its buffer and one that
 * waited in it, on both sides. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbInsnDataCacheArbiterCheck import CachePkg::*, AtomicPkg::*; #(
    parameter POLICY        = ARB_ROUND_ROBIN,
    parameter PENDING_WIDTH = 1
)(
    input  wire  clk,
    output logic done
);
`ifdef VERILATOR
    localparam N_CLOCKS = 20000;
`else
    localparam N_CLOCKS = 2000;     // about 1 s at most for a library test
`endif
    localparam AW  = 16;
    localparam DW  = 32;
    localparam SW  = DW / 8;
    localparam CAP = 1 << PENDING_WIDTH;    // reads in memory at most
    localparam Q   = 8;                     // room of the model queues
    localparam logic SIDE_I = 1'b0;
    localparam logic SIDE_D = 1'b1;

    logic          rst_n;
    logic [1:0]    prio;
    // Instruction cache
    logic          i_valid;
    wire           i_ready;
    logic [AW-1:0] i_addr;
    wire           i_rsp_valid;
    wire  [DW-1:0] i_rsp_data;
    // Data cache
    logic          d_valid;
    wire           d_ready;
    logic          d_we;
    logic [AW-1:0] d_addr;
    logic [DW-1:0] d_wdata;
    logic [SW-1:0] d_wstrb;
    atop_t         d_atop;     // a read's atop: its address's bits 8..3 here
    wire           d_rsp_valid;
    wire  [DW-1:0] d_rsp_data;
    // Memory
    wire           m_valid;
    logic          m_ready;
    wire           m_we;
    wire  [AW-1:0] m_addr;
    wire  [2:0]    m_size;     // a request's size: its address's low bits here
    atop_t         m_atop;
    wire  [DW-1:0] m_wdata;
    wire  [SW-1:0] m_wstrb;
    logic          m_rsp_valid;
    logic [DW-1:0] m_rsp_data;

    InsnDataCacheArbiter #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .POLICY(POLICY),
                           .PENDING_WIDTH(PENDING_WIDTH)) u_insn_data_cache_arbiter(
        .clk, .rst_n, .prio,
        .icache_req_valid(i_valid), .icache_req_ready(i_ready), .icache_req_addr(i_addr),
        .icache_req_size(i_addr[2:0]),
        .icache_rsp_valid(i_rsp_valid), .icache_rsp_data(i_rsp_data),
        .dcache_req_valid(d_valid), .dcache_req_ready(d_ready), .dcache_req_we(d_we),
        .dcache_req_addr(d_addr), .dcache_req_wdata(d_wdata), .dcache_req_wstrb(d_wstrb),
        .dcache_req_size(d_addr[2:0]), .dcache_req_atop(d_atop),
        .dcache_rsp_valid(d_rsp_valid), .dcache_rsp_data(d_rsp_data),
        .mem_req_valid(m_valid), .mem_req_ready(m_ready), .mem_req_we(m_we),
        .mem_req_addr(m_addr), .mem_req_wdata(m_wdata), .mem_req_wstrb(m_wstrb),
        .mem_req_size(m_size), .mem_req_atop(m_atop), .mem_rsp_valid(m_rsp_valid),
        .mem_rsp_data(m_rsp_data));

    assign d_atop = d_we ? ATOP_NONE : d_addr[8:3];

    // Model queues: reads a cache waits for (addresses), reads in memory (address, side,
    // the clock its answer may come).
    logic [AW-1:0] iq [Q];
    logic [AW-1:0] dq [Q];
    logic [AW-1:0] mq_addr [Q];
    logic          mq_side [Q];
    integer        mq_time [Q];
    integer        ih, it, dh, dt, mh, mt;  // heads and tails, counts of pushes and pops

    // The model of the buffers: a request taken from a cache that memory did not take yet.
    logic          ib_full;
    logic [AW-1:0] ib_addr;
    logic          db_full;
    logic          db_we;
    logic [AW-1:0] db_addr;
    logic [DW-1:0] db_wdata;
    logic [SW-1:0] db_wstrb;
    // Behind the buffers: the request of each side the arbiter sees.
    logic          ci_valid, cd_valid, cd_we;
    logic [AW-1:0] ci_addr, cd_addr;
    logic [DW-1:0] cd_wdata;
    logic [SW-1:0] cd_wstrb;

    integer        now;
    integer        seed;
    logic          last;        // the side memory took the last request from
    logic          held;        // the request presented in the clock before was not taken
    logic          h_side;      // that request
    logic          h_we;
    logic [AW-1:0] h_addr;
    logic [DW-1:0] h_wdata;
    logic [SW-1:0] h_wstrb;
    logic          side;        // the side presented now
    logic          i_take, d_take, m_take, ci_take, cd_take, ci_ok, cd_ok, rsp, rsp_d, exp_valid;
    integer        n_prio_d, n_prio_i, n_policy, n_held, n_full, n_rsp_i, n_rsp_d;
    integer        n_flow_i, n_flow_d, n_wait_i, n_wait_d;
    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0]   rnd;
    /* verilator lint_on UNUSEDSIGNAL */

    // The line memory has at an address.
    function automatic logic [DW-1:0] line_of(input logic [AW-1:0] a);
        return {~a, a};
    endfunction

    // Who takes memory in a tie: prio, else POLICY.
    function automatic logic tie_side(input logic [1:0] p, input logic l);
        if (p == PRIO_DATA) return SIDE_D;
        if (p == PRIO_INSN) return SIDE_I;
        if (POLICY == ARB_DATA_FIRST) return SIDE_D;
        if (POLICY == ARB_INSN_FIRST) return SIDE_I;
        return !l;
    endfunction

    // Before the rising edge: checks, and what the edge does.
    task automatic check();
        if (i_ready !== !ib_full || d_ready !== !db_full)
            $fatal(1, "Arbiter %0d: ready instruction %b data %b, buffers full %b %b",
                   POLICY, i_ready, d_ready, ib_full, db_full);
        i_take   = i_valid && i_ready;
        d_take   = d_valid && d_ready;
        ci_valid = ib_full || i_valid;
        ci_addr  = ib_full ? ib_addr : i_addr;
        cd_valid = db_full || d_valid;
        cd_we    = db_full ? db_we : d_we;
        cd_addr  = db_full ? db_addr : d_addr;
        cd_wdata = db_full ? db_wdata : d_wdata;
        cd_wstrb = db_full ? db_wstrb : d_wstrb;
        ci_ok    = ci_valid && (mt - mh) < CAP;
        cd_ok    = cd_valid && (cd_we || (mt - mh) < CAP);
        if (held)                side = h_side;
        else if (ci_ok && cd_ok) side = tie_side(prio, last);
        else                     side = cd_ok ? SIDE_D : SIDE_I;
        exp_valid = (side == SIDE_D) ? cd_ok : ci_ok;
        if (m_valid !== exp_valid)
            $fatal(1, "Arbiter %0d: memory request %b, expected %b of side %b (%0d reads in memory)",
                   POLICY, m_valid, exp_valid, side, mt - mh);
        if (m_valid && side == SIDE_I && (m_we || m_addr !== ci_addr))
            $fatal(1, "Arbiter %0d: instruction read %h, memory got we=%b %h",
                   POLICY, ci_addr, m_we, m_addr);
        if (m_valid && side == SIDE_D &&
            (m_we !== cd_we || m_addr !== cd_addr ||
             (cd_we && (m_wdata !== cd_wdata || m_wstrb !== cd_wstrb))))
            $fatal(1, "Arbiter %0d: data request we=%b %h %h %h, memory got we=%b %h %h %h",
                   POLICY, cd_we, cd_addr, cd_wdata, cd_wstrb, m_we, m_addr, m_wdata, m_wstrb);
        if (m_valid && m_size !== m_addr[2:0])
            $fatal(1, "InsnDataCacheArbiter %0d: mem_req_size %0d of %h, expected %0d",
                   POLICY, m_size, m_addr, m_addr[2:0]);
        if (m_valid && m_atop !== ((side == SIDE_D && !m_we) ? m_addr[8:3] : ATOP_NONE))
            $fatal(1, "InsnDataCacheArbiter %0d: mem_req_atop %h of side %b, %h",
                   POLICY, m_atop, side, m_addr);
        if (held && (m_valid !== 1'b1 || m_we !== h_we || m_addr !== h_addr ||
                     (h_we && (m_wdata !== h_wdata || m_wstrb !== h_wstrb))))
            $fatal(1, "Arbiter %0d: the request held changed: valid=%b we=%b %h, was we=%b %h",
                   POLICY, m_valid, m_we, m_addr, h_we, h_addr);
        m_take  = m_valid && m_ready;
        ci_take = m_take && side == SIDE_I;
        cd_take = m_take && side == SIDE_D;
        if (m_take && !held && ci_ok && cd_ok) begin
            if (prio == PRIO_DATA)      n_prio_d = n_prio_d + 1;
            else if (prio == PRIO_INSN) n_prio_i = n_prio_i + 1;
            else                        n_policy = n_policy + 1;
        end
        if (held)
            n_held = n_held + 1;
        if ((mt - mh) == CAP && cd_take && cd_we && ci_valid)
            n_full = n_full + 1;
        if (i_take && ci_take)  n_flow_i = n_flow_i + 1;
        if (i_take && !ci_take) n_wait_i = n_wait_i + 1;
        if (d_take && cd_take)  n_flow_d = n_flow_d + 1;
        if (d_take && !cd_take) n_wait_d = n_wait_d + 1;
        // Answers.
        rsp   = m_rsp_valid;
        rsp_d = mq_side[mh % Q];
        if (i_rsp_valid !== (rsp && !rsp_d) || d_rsp_valid !== (rsp && rsp_d))
            $fatal(1, "Arbiter %0d: answer %b of side %b, instruction cache got %b, data cache %b",
                   POLICY, rsp, rsp_d, i_rsp_valid, d_rsp_valid);
        if (rsp && !rsp_d && (ih == it || i_rsp_data !== line_of(iq[ih % Q])))
            $fatal(1, "Arbiter %0d: instruction cache answer %h, expected the line of %h",
                   POLICY, i_rsp_data, iq[ih % Q]);
        if (rsp && rsp_d && (dh == dt || d_rsp_data !== line_of(dq[dh % Q])))
            $fatal(1, "Arbiter %0d: data cache answer %h, expected the line of %h",
                   POLICY, d_rsp_data, dq[dh % Q]);
        held    = m_valid && !m_ready;
        h_side  = side;
        h_we    = m_we;
        h_addr  = m_addr;
        h_wdata = m_wdata;
        h_wstrb = m_wstrb;
    endtask

    // The cut: within the clock, the other side's valid and memory's ready do not move a
    // cache's ready (they are put back before the edge).
    task automatic check_cut();
        logic ir, dr;
        ir = i_ready;
        dr = d_ready;
        d_valid = !d_valid;
        #1 if (i_ready !== ir)
            $fatal(1, "Arbiter %0d: the data cache's valid moved the instruction cache's ready", POLICY);
        d_valid = !d_valid;
        i_valid = !i_valid;
        #1 if (d_ready !== dr)
            $fatal(1, "Arbiter %0d: the instruction cache's valid moved the data cache's ready", POLICY);
        i_valid = !i_valid;
        m_ready = !m_ready;
        #1 if (i_ready !== ir || d_ready !== dr)
            $fatal(1, "Arbiter %0d: memory's ready moved a cache's ready", POLICY);
        m_ready = !m_ready;
    endtask

    // After the rising edge: the models do what the edge did and drive the next clock.
    task automatic advance();
        if (rsp) begin
            if (rsp_d) begin dh = dh + 1; n_rsp_d = n_rsp_d + 1; end
            else       begin ih = ih + 1; n_rsp_i = n_rsp_i + 1; end
            mh = mh + 1;
        end
        // The buffers: an empty one loads the cache's request; a request offered behind it and
        // not taken by memory is in it after the edge.
        if (!ib_full)
            ib_addr = i_addr;
        if (!db_full)
            {db_we, db_addr, db_wdata, db_wstrb} = {d_we, d_addr, d_wdata, d_wstrb};
        ib_full = ci_valid && !ci_take;
        db_full = cd_valid && !cd_take;
        if (i_take) begin
            i_valid = 1'b0;
            iq[it % Q] = i_addr;
            it = it + 1;
        end
        if (d_take) begin
            d_valid = 1'b0;
            if (!d_we) begin
                dq[dt % Q] = d_addr;
                dt = dt + 1;
            end
        end
        if (m_take) begin
            last = side;
            if (!h_we) begin
                rnd = $random(seed);
                mq_addr[mt % Q] = h_addr;
                mq_side[mt % Q] = side;
                mq_time[mt % Q] = now + 1 + int'(rnd[2:0]) % 6;
                mt = mt + 1;
            end
        end
        // The answer of this clock: the oldest read, when its time has come.
        m_rsp_valid = mh != mt && mq_time[mh % Q] <= now + 1;
        m_rsp_data  = m_rsp_valid ? line_of(mq_addr[mh % Q]) : '0;
        // New requests: a cache with a free request slot asks sometimes; at most CAP reads
        // each, so that together they can fill the queue.
        rnd = $random(seed);
        if (!i_valid && rnd[0] && it - ih < CAP) begin
            i_valid = 1'b1;
            i_addr  = AW'($random(seed));
        end
        if (!d_valid && rnd[1] && dt - dh < CAP) begin
            d_valid = 1'b1;
            d_we    = rnd[2];
            d_addr  = AW'($random(seed));
            d_wdata = $random(seed);
            d_wstrb = rnd[7:4];
        end
        m_ready = rnd[9:8] != 2'b00;
        prio    = (rnd[11:10] == 2'd3) ? PRIO_NONE : rnd[11:10];
        now = now + 1;
    endtask

    initial begin
        done = 1'b0;
        seed = 1 + POLICY + 8 * PENDING_WIDTH;
        {ih, it, dh, dt, mh, mt} = '0;
        {n_prio_d, n_prio_i, n_policy, n_held, n_full, n_rsp_i, n_rsp_d} = '0;
        {n_flow_i, n_flow_d, n_wait_i, n_wait_d} = '0;
        now = 0;
        last = SIDE_D;          // the arbiter after reset: the instruction cache first
        held = 1'b0;
        h_side = SIDE_I;
        {h_we, h_addr, h_wdata, h_wstrb} = '0;
        {ib_full, db_full} = '0;
        {ib_addr, db_we, db_addr, db_wdata, db_wstrb} = '0;
        rst_n = 1'b0;
        prio = PRIO_NONE;
        {i_valid, d_valid, d_we, m_ready, m_rsp_valid} = '0;
        {i_addr, d_addr, d_wdata, d_wstrb, m_rsp_data} = '0;
        repeat (2) @(posedge clk);
        #1 rst_n = 1'b1;
        for (int c = 0; c < N_CLOCKS; c++) begin
            @(negedge clk);
            check();
            check_cut();
            @(posedge clk);
            #1 advance();
        end
        if (n_prio_d == 0 || n_prio_i == 0 || n_policy == 0 || n_held == 0 || n_full == 0 ||
            n_rsp_i == 0 || n_rsp_d == 0 || n_flow_i == 0 || n_flow_d == 0 || n_wait_i == 0 ||
            n_wait_d == 0)
            $fatal(1, {"Arbiter %0d: a case did not happen: prio %0d %0d policy %0d held %0d ",
                       "full %0d rsp %0d %0d flow %0d %0d wait %0d %0d"},
                   POLICY, n_prio_d, n_prio_i, n_policy, n_held, n_full, n_rsp_i, n_rsp_d,
                   n_flow_i, n_flow_d, n_wait_i, n_wait_d);
        done = 1'b1;
    end
endmodule

module TbInsnDataCacheArbiter;
    import CachePkg::*;
    wire clk;
    wire done_rr;
    wire done_d;
    wire done_i;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbInsnDataCacheArbiterCheck #(.POLICY(ARB_ROUND_ROBIN), .PENDING_WIDTH(1)) u_check_rr(
        .clk, .done(done_rr));
    TbInsnDataCacheArbiterCheck #(.POLICY(ARB_DATA_FIRST), .PENDING_WIDTH(1)) u_check_d(
        .clk, .done(done_d));
    TbInsnDataCacheArbiterCheck #(.POLICY(ARB_INSN_FIRST), .PENDING_WIDTH(2)) u_check_i(
        .clk, .done(done_i));

    initial begin
        wait (done_rr && done_d && done_i);
        $finish;
    end
endmodule
