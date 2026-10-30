/* Test of SkewedCacheRdOnly.
 *
 * As the test of SetAssocCacheRdOnly: random, the way a CPU fetches through the cache (a
 * request in most clocks, held until the cache takes it), to addresses of a few tags per set,
 * so that lines are evicted and come back, often to the set of the request before; a memory
 * that takes a line request in 70 % of the clocks and answers it after 1 to 4 clocks; now and
 * then an invalidate while no miss is served, after which the memory has new content (a line
 * kept valid by mistake answers old data). A model of its own keeps per way and line index
 * the valid bit, tag, line and recent bit; the index of a line is set in way 0 and set ^ the
 * low bits of the tag in way 1. It checks in every clock req_ready, mem_req_valid with the
 * line address, rsp_valid and rsp_data, against the hit or miss it computes; mem_req_valid
 * must be 0 during reset. Its victim, taken when memory takes the read: an invalid candidate
 * as read with the request (way 1 first), else the one whose recent bit is clear, else way 0;
 * a hit or a fill sets its line's recent bit and clears the other candidate's. In the end the
 * test checks that every case happened: hits in both ways, hits in way 1 at an index other
 * than way 0's (the skew), back-to-back hits, misses, evictions by the recent bits and by the
 * tie rule, misses on a line an invalidate cleared, requests that wait for req_ready, a line
 * request that waits for memory, both memory latencies.
 * Verilator runs 8 lines per way with 12-bit addresses and 64 lines per way with 32-bit
 * addresses, 20000 clocks each; Icarus 8 lines, 600 clocks. Stops at the first mismatch with
 * $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbSkewedCacheCheck #(
    parameter ADDR_WIDTH  = 12,
    parameter SETS_WIDTH  = 3,      // up to 8
    parameter SETS_OFFSET = 2
)(
    input  wire  clk,
    output logic done
);
    localparam DATA_WIDTH  = 8 << SETS_OFFSET;
    localparam TAG_WIDTH   = ADDR_WIDTH - SETS_WIDTH - SETS_OFFSET;    // SETS_WIDTH or more
    localparam SETS        = 1 << SETS_WIDTH;
`ifdef VERILATOR
    localparam N_CLOCKS    = 20000;
`else
    localparam N_CLOCKS    = 600;   // about 1 s at most for a library test (struct)
`endif
    localparam TAGS        = 5;     // tags of the addresses: lines are evicted, come back
    localparam MAX_LATENCY = 4;     // clocks from a line request to the answer of memory

    typedef logic [TAG_WIDTH-1:0]   tag_t;
    typedef logic [SETS_WIDTH-1:0]  set_t;
    typedef logic [SETS_OFFSET-1:0] offset_t;
    typedef logic [DATA_WIDTH-1:0]  data_t;
    typedef struct packed {
        tag_t    tag;
        set_t    set;
        offset_t offset;
    } addr_t;                       // a byte address as the cache takes it apart

    logic  rst_n;
    logic  invalidate;
    logic  req_valid;
    addr_t req_addr;
    wire   req_ready;
    wire   rsp_valid;
    data_t rsp_data;
    wire   mem_req_valid;
    logic  mem_req_ready;
    addr_t mem_req_addr;
    logic  mem_rsp_valid;
    data_t mem_rsp_data;

    // Model of the cache, 2-state, per way and line index.
    bit                  m_valid  [2][SETS];
    bit [TAG_WIDTH-1:0]  m_tag    [2][SETS];
    bit [DATA_WIDTH-1:0] m_data   [2][SETS];
    bit                  m_lost   [2][SETS];    // the line was valid when an invalidate came
    bit                  m_recent [2][SETS];
    integer              epoch;                 // memory content: new after every invalidate

    // What the model expects in this clock.
    logic   look;           // a request taken before is looked up now (or held)
    logic   req_taken;      // the cache took the request at the edge before
    addr_t  look_addr;
    logic   look_hit;
    integer look_way;       // its way, when it hits
    data_t  look_data;      // its line, when it hits
    bit     look_valid [2]; // valid bits of its candidates as read with the request
    logic   waiting;        // a miss is served
    addr_t  wait_line;      // its line address
    integer wait_way;       // the way its line goes into
    integer mem_count;      // clocks until memory answers, 0: no line request in flight
    integer mem_latency;    // latency of the line request in flight
    set_t   last_set;       // set of the last request

    tag_t   pool [TAGS];
    integer seed;

    // Cases seen.
    integer n_hit0;
    integer n_hit1;
    integer n_hit1_skewed;      // a hit in way 1 at an index other than way 0's
    integer n_hit_b2b;
    integer n_miss;
    integer n_by_recent;        // a victim chosen by the recent bits
    integer n_by_tie;           // a victim chosen by the tie rule
    integer n_lost;
    integer n_waited;           // a request waits for req_ready
    integer n_mem_held;         // a line request waits for memory
    integer n_lat1;
    integer n_lat_more;

    SkewedCacheRdOnly #(.ADDR_WIDTH(ADDR_WIDTH), .SETS_WIDTH(SETS_WIDTH),
                        .SETS_OFFSET(SETS_OFFSET))
        u_skewed_cache_rd_only(
            .clk, .rst_n, .invalidate, .req_valid, .req_addr, .req_ready, .rsp_valid,
            .rsp_data, .mem_req_valid, .mem_req_ready, .mem_req_addr, .mem_rsp_valid,
            .mem_rsp_data);

    // The address of the line of a: offset 0.
    function automatic addr_t line_of(input addr_t a);
        addr_t l;
        l        = a;
        l.offset = '0;
        return l;
    endfunction

    // The index of the line of a in way w: the set, in way 1 xor the low bits of the tag (the
    // offset and the higher bits of the tag do not matter).
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic set_t index_of(input integer w, input addr_t a);
        return (w == 0) ? a.set : a.set ^ a.tag[SETS_WIDTH-1:0];
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // Memory content: a line of each address, different in every epoch.
    function automatic data_t mem_line(input addr_t line, input integer ep);
        data_t d;
        for (int i = 0; i < DATA_WIDTH / 32; i++)
            d[32*i +: 32] = (32'(line) * 32'h9E37_79B1) ^ (32'(ep) * 32'h85EB_CA77) ^ 32'(i);
        return d;
    endfunction

    function automatic logic model_ready;
        return !waiting && !(look && !look_hit);
    endfunction

    // The way a miss replaces: an invalid candidate as read with the request (way 1 first),
    // else the one whose recent bit is clear, else way 0.
    function automatic integer model_victim(input addr_t a);
        bit r0;
        bit r1;
        if (!look_valid[1]) return 1;
        if (!look_valid[0]) return 0;
        r0 = m_recent[0][index_of(0, a)];
        r1 = m_recent[1][index_of(1, a)];
        if (r0 != r1) begin
            n_by_recent = n_by_recent + 1;
            return r0 ? 1 : 0;
        end
        n_by_tie = n_by_tie + 1;
        return 0;
    endfunction

    // A hit or a fill of way w for the line of a: it becomes recent, the other candidate not.
    task automatic touch(input integer w, input addr_t a);
        m_recent[0][index_of(0, a)] = (w == 0);
        m_recent[1][index_of(1, a)] = (w == 1);
    endtask

    // After the inputs of this clock settled: the outputs are those of the model.
    task automatic check;
        logic  exp_mem_req;
        logic  exp_rsp;
        data_t exp_data;
        exp_mem_req = look && !look_hit;
        exp_rsp     = (look && look_hit) || (waiting && mem_rsp_valid);
        exp_data    = waiting ? mem_rsp_data : look_data;
        if (req_ready !== model_ready() || mem_req_valid !== exp_mem_req ||
            (exp_mem_req && mem_req_addr !== line_of(look_addr)) || rsp_valid !== exp_rsp ||
            (exp_rsp && rsp_data !== exp_data))
            $fatal(1, "Skewed cache %0d: ready %b mem_req %b %h rsp %b %h, expected %b %b %h %b %h",
                   SETS, req_ready, mem_req_valid, mem_req_addr, rsp_valid, rsp_data,
                   model_ready(), exp_mem_req, line_of(look_addr), exp_rsp, exp_data);
    endtask

    // Model of one rising edge with the inputs of this clock.
    task automatic model_edge;
        logic   accept;
        logic   held;
        logic   was_look_hit;
        set_t   ix;
        accept       = req_valid && model_ready();
        held         = look && !look_hit && !mem_req_ready;
        was_look_hit = look && look_hit;
        if (req_valid && !model_ready())
            n_waited = n_waited + 1;
        if (held)
            n_mem_held = n_mem_held + 1;
        // The lookup of this clock: a hit touches its line; a miss, when memory takes its
        // read, takes its victim; the memory's answer fills the line.
        if (look && look_hit) begin
            touch(look_way, look_addr);
        end else if (look && !look_hit && mem_req_ready) begin
            waiting     = 1'b1;
            wait_line   = line_of(look_addr);
            wait_way    = model_victim(look_addr);
            mem_latency = 1 + {$random(seed)} % MAX_LATENCY;
            mem_count   = mem_latency;
        end else if (waiting && mem_rsp_valid) begin
            ix                     = index_of(wait_way, wait_line);
            m_valid[wait_way][ix]  = 1'b1;
            m_tag[wait_way][ix]    = wait_line.tag;
            m_data[wait_way][ix]   = mem_rsp_data;
            m_lost[wait_way][ix]   = 1'b0;
            touch(wait_way, wait_line);
            waiting                = 1'b0;
        end
        // A request is looked up with the lines as they are before this edge; a held lookup
        // stays as it is.
        look      = accept || held;
        req_taken = accept;     // req_valid stays until after the edge
        if (accept) begin
            look_addr = req_addr;
            look_hit  = 1'b0;
            for (int w = 0; w < 2; w++) begin
                ix            = index_of(w, req_addr);
                look_valid[w] = m_valid[w][ix];
                if (m_valid[w][ix] && m_tag[w][ix] == req_addr.tag) begin
                    look_hit  = 1'b1;
                    look_way  = w;
                    look_data = m_data[w][ix];
                end
            end
            if (look_hit) begin
                if (look_way == 0) n_hit0 = n_hit0 + 1;
                else               n_hit1 = n_hit1 + 1;
                if (look_way == 1 && index_of(1, req_addr) != index_of(0, req_addr))
                    n_hit1_skewed = n_hit1_skewed + 1;
                if (was_look_hit)
                    n_hit_b2b = n_hit_b2b + 1;
            end else begin
                n_miss = n_miss + 1;
                for (int w = 0; w < 2; w++) begin
                    ix = index_of(w, req_addr);
                    if (m_lost[w][ix] && m_tag[w][ix] == req_addr.tag)
                        n_lost = n_lost + 1;
                end
            end
        end
        if (invalidate) begin
            for (int w = 0; w < 2; w++)
                for (int i = 0; i < SETS; i++) begin
                    m_lost[w][i]  = m_valid[w][i];
                    m_valid[w][i] = 1'b0;
                end
            epoch = epoch + 1;
        end
    endtask

    task automatic random_test;
        // Bits of r: 0..2 request, 3..8 invalidate, 9..11 tag, 12..13 same set, 16 and up
        // offset and set; the rest unused.
        /* verilator lint_off UNUSEDSIGNAL */
        integer r;
        /* verilator lint_on UNUSEDSIGNAL */
        for (int k = 0; k < N_CLOCKS; k++) begin
            r = $random(seed);
            // The CPU holds a request until it is taken, then may send the next.
            if (req_taken)
                req_valid = 1'b0;
            if (!req_valid && r[2:0] != 3'b000) begin
                req_valid       = 1'b1;
                req_addr.tag    = pool[r[11:9] % TAGS];
                req_addr.set    = r[13:12] == 2'b00 ? r[16 + SETS_OFFSET +: SETS_WIDTH] :
                                                      last_set;
                req_addr.offset = r[16 +: SETS_OFFSET];
                last_set        = req_addr.set;
            end
            mem_req_ready = ($unsigned($random(seed)) % 10) < 7;
            // Invalidate only while no miss is served (the rule of the cache).
            invalidate = r[8:3] == 6'd0 && !waiting && !(look && !look_hit);
            // Memory: the answer to the line request in flight, after its latency.
            mem_rsp_valid = 1'b0;
            if (mem_count > 0) begin
                mem_count = mem_count - 1;
                if (mem_count == 0) begin
                    mem_rsp_valid = 1'b1;
                    mem_rsp_data  = mem_line(wait_line, epoch);
                    if (mem_latency == 1)
                        n_lat1 = n_lat1 + 1;
                    else
                        n_lat_more = n_lat_more + 1;
                end
            end
            #1;
            check();
            model_edge();
            @(negedge clk);
        end
        req_valid     = 1'b0;
        invalidate    = 1'b0;
        mem_rsp_valid = 1'b0;
    endtask

    initial begin
        done          = 1'b0;
        seed          = SETS_WIDTH * 16 + ADDR_WIDTH;
        n_hit0        = 0;
        n_hit1        = 0;
        n_hit1_skewed = 0;
        n_hit_b2b     = 0;
        n_miss        = 0;
        n_by_recent   = 0;
        n_by_tie      = 0;
        n_lost        = 0;
        n_waited      = 0;
        n_mem_held    = 0;
        n_lat1        = 0;
        n_lat_more    = 0;
        // Different tags, with random high bits and different low bits (the skew of way 1).
        for (int t = 0; t < TAGS; t++)
            pool[t] = (TAG_WIDTH'($random(seed)) & ~TAG_WIDTH'(7)) | TAG_WIDTH'(t);
        for (int w = 0; w < 2; w++)
            for (int i = 0; i < SETS; i++) begin
                m_valid[w][i]  = 1'b0;
                m_lost[w][i]   = 1'b0;
                m_recent[w][i] = 1'b0;
            end
        epoch       = 0;
        look        = 1'b0;
        req_taken   = 1'b0;
        look_addr   = '0;
        look_hit    = 1'b0;
        look_way    = 0;
        look_data   = '0;
        waiting     = 1'b0;
        wait_line   = '0;
        wait_way    = 0;
        mem_count   = 0;
        mem_latency = 0;
        last_set    = '0;
        rst_n       = 1'b0;
        invalidate  = 1'b0;
        req_valid   = 1'b0;
        req_addr    = '0;
        mem_req_ready = 1'b0;
        mem_rsp_valid = 1'b0;
        mem_rsp_data  = '0;
        // Reset: every line invalid, and no line request.
        @(negedge clk);
        @(negedge clk);
        if (mem_req_valid !== 1'b0)
            $fatal(1, "Skewed cache %0d: mem_req_valid %b during reset", SETS, mem_req_valid);
        rst_n = 1'b1;
        random_test();
        if (n_hit0 == 0 || n_hit1 == 0 || n_hit1_skewed == 0 || n_hit_b2b == 0 ||
            n_miss == 0 || n_by_recent == 0 || n_by_tie == 0 || n_lost == 0 || n_waited == 0 ||
            n_mem_held == 0 || n_lat1 == 0 || n_lat_more == 0)
            $fatal(1, "Skewed cache %0d: a case did not happen: %0d %0d %0d %0d, %0d %0d %0d %0d, %s %0d %0d %0d %0d",
                   SETS, n_hit0, n_hit1, n_hit1_skewed, n_hit_b2b, n_miss, n_by_recent, n_by_tie,
                   n_lost, "waited, held, latency", n_waited, n_mem_held, n_lat1, n_lat_more);
        done = 1'b1;
    end
endmodule

module TbSkewedCacheRdOnly;
`ifdef VERILATOR
    localparam bit WIDE = 1'b1;     // also 64 lines per way with 32-bit addresses
`else
    localparam bit WIDE = 1'b0;
`endif
    wire clk;
    wire done_8;
    wire done_64;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbSkewedCacheCheck u_check_8(.clk, .done(done_8));
    if (WIDE) begin: g_wide
        TbSkewedCacheCheck #(.ADDR_WIDTH(32), .SETS_WIDTH(6)) u_check_64(.clk, .done(done_64));
    end else begin: g_narrow
        assign done_64 = 1'b1;
    end

    initial begin
        wait (done_8 && done_64);
        $display("PASS");
        $finish;
    end
endmodule
