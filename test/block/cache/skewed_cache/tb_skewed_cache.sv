/* Test of SkewedCache.
 *
 * As the test of SetAssocCache: random, the way a CPU loads and stores through the cache (a
 * request in most clocks, a third of them stores with random bytes and strobes, held until
 * the cache takes it), to addresses of a few tags per set, so that lines are evicted and come
 * back, often the line or set of the request before; a memory that takes a request in 70 %
 * of the clocks, keeps the lines (a model of its own, changed by the stores it takes) and
 * answers each read after 1 to 4 clocks; now and then an invalidate while no load miss is
 * served, after which the memory has new content. A model of the cache keeps per way and
 * line index the valid bit, tag, line and recent bit; the index of a line is set in way 0
 * and set ^ the low bits of the tag in way 1. It checks in every clock req_ready,
 * mem_req_valid with the fields of the request, rsp_valid and rsp_data; mem_req_valid must be
 * 0 during reset. The victim of a load miss, taken when memory takes the read: an invalid
 * candidate as read with the request (way 1 first), else the one whose recent bit is clear,
 * else way 0; a load hit, a store hit when memory takes it and a fill set their line's recent
 * bit and clear the other candidate's. In the end the test checks that every case happened:
 * load hits in both ways, in way 1 at an index other than way 0's (the skew), load misses,
 * store hits (also with only some bytes) and misses, a load hit right after a store hit of
 * the same line (forwarding), of the other way and of the same way at another index,
 * evictions by the recent bits and by the tie rule, a store and a read held by memory, a miss
 * on a line an invalidate cleared, both memory latencies.
 * Icarus runs 8 lines per way with lines of one word and of two words (8 strobes), 12-bit
 * addresses, 1000 clocks; Verilator also 64 lines per way with 32-bit addresses, 20000 clocks
 * each. Stops at the first mismatch with $fatal.
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
    localparam STRB_WIDTH  = 1 << SETS_OFFSET;
    localparam TAG_WIDTH   = ADDR_WIDTH - SETS_WIDTH - SETS_OFFSET;    // SETS_WIDTH or more
    localparam SETS        = 1 << SETS_WIDTH;
`ifdef VERILATOR
    localparam N_CLOCKS    = 20000;
`else
    localparam N_CLOCKS    = 1000;
`endif
    localparam TAGS        = 5;     // tags of the addresses: lines are evicted, come back
    localparam MAX_LATENCY = 4;     // clocks from a read taken to the answer of memory

    typedef logic [TAG_WIDTH-1:0]   tag_t;
    typedef logic [SETS_WIDTH-1:0]  set_t;
    typedef logic [SETS_OFFSET-1:0] offset_t;
    typedef logic [DATA_WIDTH-1:0]  data_t;
    typedef logic [STRB_WIDTH-1:0]  strb_t;
    typedef struct packed {
        tag_t    tag;
        set_t    set;
        offset_t offset;
    } addr_t;                       // a byte address as the cache takes it apart

    logic  rst_n;
    logic  invalidate;
    logic  req_valid;
    wire   req_ready;
    logic  req_we;
    addr_t req_addr;
    data_t req_wdata;
    strb_t req_wstrb;
    wire   rsp_valid;
    data_t rsp_data;
    wire   mem_req_valid;
    logic  mem_req_ready;
    wire   mem_req_we;
    addr_t mem_req_addr;
    data_t mem_req_wdata;
    strb_t mem_req_wstrb;
    logic  mem_rsp_valid;
    data_t mem_rsp_data;

    // Model of the memory: the line of every address the test uses (tag of the pool, set).
    bit [DATA_WIDTH-1:0] mem [TAGS][SETS];
    integer              epoch;                 // memory content: new after every invalidate

    // Model of the cache, 2-state, per way and line index.
    bit                  m_valid  [2][SETS];
    bit [TAG_WIDTH-1:0]  m_tag    [2][SETS];
    bit [DATA_WIDTH-1:0] m_data   [2][SETS];
    bit                  m_lost   [2][SETS];    // the line was valid when an invalidate came
    bit                  m_recent [2][SETS];

    // What the model expects in this clock.
    logic   look;           // a request taken before is looked up now (or held)
    addr_t  look_addr;
    logic   look_we;
    data_t  look_wdata;
    strb_t  look_wstrb;
    logic   look_hit;
    integer look_way;       // its way, when it hits
    data_t  look_data;      // its line, when it hits
    bit     look_valid [2]; // valid bits of its candidates as read with the request
    logic   req_taken;      // the cache took the request at the edge before
    logic   waiting;        // a load miss is served
    addr_t  wait_line;      // its line address
    integer wait_way;       // the way its line goes into
    data_t  wait_data;      // the line memory answers with
    integer mem_count;      // clocks until memory answers, 0: no read in flight
    integer mem_latency;    // latency of the read in flight
    logic   stored;         // at this edge, a store that hits is taken by memory
    integer stored_way;
    set_t   stored_index;   // its index in its way

    tag_t   pool [TAGS];
    integer seed;

    // Cases seen.
    integer n_load_hit0;
    integer n_load_hit1;
    integer n_hit1_skewed;      // a load hit in way 1 at an index other than way 0's
    integer n_load_miss;
    integer n_store_hit;
    integer n_store_partial;    // a store hit with only some bytes
    integer n_store_miss;
    integer n_fwd;              // a load hit right after a store hit of the same line
    integer n_fwd_ways;         // ... of the other way
    integer n_fwd_index;        // ... of the same way at another index
    integer n_by_recent;        // a victim chosen by the recent bits
    integer n_by_tie;           // a victim chosen by the tie rule
    integer n_store_held;
    integer n_read_held;
    integer n_lost;
    integer n_lat1;
    integer n_lat_more;
    logic [16:0] missing;       // the cases that did not happen, in the order of the list

    SkewedCache #(.ADDR_WIDTH(ADDR_WIDTH), .SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET))
        u_skewed_cache(
            .clk, .rst_n, .invalidate,
            .req_valid, .req_ready, .req_we, .req_addr, .req_wdata, .req_wstrb,
            .rsp_valid, .rsp_data,
            .mem_req_valid, .mem_req_ready, .mem_req_we, .mem_req_addr, .mem_req_wdata,
            .mem_req_wstrb, .mem_rsp_valid, .mem_rsp_data);

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

    // Index of a tag in the pool (the tags of every address the test uses).
    function automatic integer tag_index(input tag_t t);
        for (int i = 0; i < TAGS; i++)
            if (pool[i] == t)
                return i;
        $fatal(1, "SkewedCache %0d: tag %h is not in the pool", SETS, t);
        return 0;
    endfunction

    // Memory content of a line in an epoch.
    function automatic data_t mem_line(input integer t, input integer s, input integer ep);
        data_t d;
        for (int i = 0; i < DATA_WIDTH / 32; i++)
            d[32*i +: 32] = (32'(t * SETS + s) * 32'h9E37_79B1) ^ (32'(ep) * 32'h85EB_CA77) ^
                            32'(i);
        return d;
    endfunction

    function automatic data_t merge(input data_t old, input data_t new_bytes, input strb_t strb);
        data_t d;
        d = old;
        for (int b = 0; b < STRB_WIDTH; b++)
            if (strb[b])
                d[8*b +: 8] = new_bytes[8*b +: 8];
        return d;
    endfunction

    function automatic logic exp_store;
        return look && look_we;
    endfunction

    function automatic logic exp_load_miss;
        return look && !look_we && !look_hit;
    endfunction

    function automatic logic exp_mem_valid;
        return exp_store() || exp_load_miss();
    endfunction

    function automatic logic exp_ready;
        return !waiting && !exp_load_miss() && !(exp_mem_valid() && !mem_req_ready);
    endfunction

    // The way a load miss replaces: an invalid candidate as read with the request (way 1
    // first), else the one whose recent bit is clear, else way 0.
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

    // A touch of way w for the line of a: it becomes recent, the other candidate not.
    task automatic touch(input integer w, input addr_t a);
        m_recent[0][index_of(0, a)] = (w == 0);
        m_recent[1][index_of(1, a)] = (w == 1);
    endtask

    // After the inputs of this clock settled: the outputs are those of the model.
    task automatic check;
        logic  exp_rsp;
        data_t exp_data;
        exp_rsp  = (look && !look_we && look_hit) || (waiting && mem_rsp_valid);
        exp_data = waiting ? mem_rsp_data : look_data;
        if (req_ready !== exp_ready() || mem_req_valid !== exp_mem_valid() ||
            rsp_valid !== exp_rsp || (exp_rsp && rsp_data !== exp_data))
            $fatal(1, "SkewedCache %0d: ready %b mem_req %b rsp %b %h, expected %b %b %b %h",
                   SETS, req_ready, mem_req_valid, rsp_valid, rsp_data, exp_ready(),
                   exp_mem_valid(), exp_rsp, exp_data);
        if (exp_mem_valid() &&
            (mem_req_we !== look_we || mem_req_addr !== line_of(look_addr) ||
             (look_we && (mem_req_wdata !== look_wdata || mem_req_wstrb !== look_wstrb))))
            $fatal(1, "SkewedCache %0d: mem_req we %b %h %h %b, expected %b %h %h %b",
                   SETS, mem_req_we, mem_req_addr, mem_req_wdata, mem_req_wstrb,
                   look_we, line_of(look_addr), look_wdata, look_wstrb);
    endtask

    // Model of one rising edge with the inputs of this clock.
    task automatic model_edge;
        logic taken;            // memory takes the lookup's request
        logic accept;
        logic held;
        set_t ix;
        taken  = exp_mem_valid() && mem_req_ready;
        held   = exp_mem_valid() && !mem_req_ready;
        accept = req_valid && exp_ready();
        stored = 1'b0;
        if (held) begin
            if (look_we) n_store_held = n_store_held + 1;
            else         n_read_held  = n_read_held + 1;
        end
        // The lookup of this clock: a load hit touches its line; a store taken by memory
        // writes memory, and when it hits its line, which it touches; a load miss taken by
        // memory takes its victim and starts its read. The memory's answer fills the line.
        if (look && !look_we && look_hit) begin
            touch(look_way, look_addr);
        end else if (taken && look_we) begin
            mem[tag_index(look_addr.tag)][look_addr.set] =
                merge(mem[tag_index(look_addr.tag)][look_addr.set], look_wdata, look_wstrb);
            if (look_hit) begin
                ix                   = index_of(look_way, look_addr);
                m_data[look_way][ix] = merge(m_data[look_way][ix], look_wdata, look_wstrb);
                touch(look_way, look_addr);
                stored       = 1'b1;
                stored_way   = look_way;
                stored_index = ix;
                n_store_hit  = n_store_hit + 1;
                if (look_wstrb != '1)
                    n_store_partial = n_store_partial + 1;
            end else
                n_store_miss = n_store_miss + 1;
        end else if (taken) begin
            waiting     = 1'b1;
            wait_line   = line_of(look_addr);
            wait_way    = model_victim(look_addr);
            wait_data   = mem[tag_index(look_addr.tag)][look_addr.set];
            mem_latency = 1 + {$random(seed)} % MAX_LATENCY;
            mem_count   = mem_latency;
        end else if (waiting && mem_rsp_valid) begin
            ix                    = index_of(wait_way, wait_line);
            m_valid[wait_way][ix] = 1'b1;
            m_tag[wait_way][ix]   = wait_line.tag;
            m_data[wait_way][ix]  = mem_rsp_data;
            m_lost[wait_way][ix]  = 1'b0;
            touch(wait_way, wait_line);
            waiting               = 1'b0;
        end
        // A request is looked up with the lines after this edge's store (forwarding); a held
        // lookup stays as it is.
        if (accept) begin
            look_addr  = req_addr;
            look_we    = req_we;
            look_wdata = req_wdata;
            look_wstrb = req_wstrb;
            look_hit   = 1'b0;
            for (int w = 0; w < 2; w++) begin
                ix            = index_of(w, req_addr);
                look_valid[w] = m_valid[w][ix];
                if (m_valid[w][ix] && m_tag[w][ix] == req_addr.tag) begin
                    look_hit  = 1'b1;
                    look_way  = w;
                    look_data = m_data[w][ix];
                end
            end
            if (!req_we && look_hit) begin
                if (look_way == 0) n_load_hit0 = n_load_hit0 + 1;
                else               n_load_hit1 = n_load_hit1 + 1;
                if (look_way == 1 && index_of(1, req_addr) != index_of(0, req_addr))
                    n_hit1_skewed = n_hit1_skewed + 1;
                if (stored && stored_way == look_way &&
                    stored_index == index_of(look_way, req_addr))
                    n_fwd = n_fwd + 1;
                if (stored && stored_way != look_way)
                    n_fwd_ways = n_fwd_ways + 1;
                if (stored && stored_way == look_way &&
                    stored_index != index_of(look_way, req_addr))
                    n_fwd_index = n_fwd_index + 1;
            end else if (!req_we) begin
                n_load_miss = n_load_miss + 1;
                for (int w = 0; w < 2; w++) begin
                    ix = index_of(w, req_addr);
                    if (m_lost[w][ix] && m_tag[w][ix] == req_addr.tag)
                        n_lost = n_lost + 1;
                end
            end
        end
        req_taken = accept;     // req_valid stays until after the edge
        look = accept || held;
        if (invalidate) begin
            for (int w = 0; w < 2; w++)
                for (int i = 0; i < SETS; i++) begin
                    m_lost[w][i]  = m_valid[w][i];
                    m_valid[w][i] = 1'b0;
                end
            epoch = epoch + 1;
            for (int ti = 0; ti < TAGS; ti++)
                for (int si = 0; si < SETS; si++)
                    mem[ti][si] = mem_line(ti, si, epoch);
        end
    endtask

    // A new request, often to the line or the set of the one before.
    task automatic new_request;
        // Bits of r: 0..1 store, 2..3 same line, 4..5 same set, 6..8 tag, 9..10 all bytes,
        // 16 and up offset and set; the rest unused.
        /* verilator lint_off UNUSEDSIGNAL */
        integer r;
        /* verilator lint_on UNUSEDSIGNAL */
        r      = $random(seed);
        req_we = r[1:0] == 2'b00 || r[1:0] == 2'b01 && r[16];
        if (r[3:2] != 2'b00) begin
            req_addr.tag = pool[r[8:6] % TAGS];
            req_addr.set = r[5:4] == 2'b00 ? r[16 + SETS_OFFSET +: SETS_WIDTH] : req_addr.set;
        end
        req_addr.offset = r[16 +: SETS_OFFSET];
        for (int i = 0; i < DATA_WIDTH / 32; i++)
            req_wdata[32*i +: 32] = $random(seed);
        req_wstrb = STRB_WIDTH'($random(seed));
        if (r[10:9] == 2'b00 || req_wstrb == '0)
            req_wstrb = '1;
        req_valid = 1'b1;
    endtask

    task automatic random_test;
        for (int k = 0; k < N_CLOCKS; k++) begin
            // The CPU holds a request until it is taken, then may send the next.
            if (req_taken)
                req_valid = 1'b0;
            if (!req_valid && ($random(seed) & 7) != 0)
                new_request();
            mem_req_ready = ($unsigned($random(seed)) % 10) < 7;
            // Invalidate only while no load miss is served (the rule of the cache).
            invalidate = ($unsigned($random(seed)) % 64) == 0 && !waiting && !exp_load_miss();
            // Memory: the answer to the read in flight, after its latency.
            mem_rsp_valid = 1'b0;
            if (mem_count > 0) begin
                mem_count = mem_count - 1;
                if (mem_count == 0) begin
                    mem_rsp_valid = 1'b1;
                    mem_rsp_data  = wait_data;
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
        done            = 1'b0;
        seed            = SETS_WIDTH * 16 + SETS_OFFSET * 4 + ADDR_WIDTH;
        n_load_hit0     = 0;
        n_load_hit1     = 0;
        n_hit1_skewed   = 0;
        n_load_miss     = 0;
        n_store_hit     = 0;
        n_store_partial = 0;
        n_store_miss    = 0;
        n_fwd           = 0;
        n_fwd_ways      = 0;
        n_fwd_index     = 0;
        n_by_recent     = 0;
        n_by_tie        = 0;
        n_store_held    = 0;
        n_read_held     = 0;
        n_lost          = 0;
        n_lat1          = 0;
        n_lat_more      = 0;
        // Different tags, with random high bits and different low bits (the skew of way 1).
        for (int t = 0; t < TAGS; t++)
            pool[t] = (TAG_WIDTH'($random(seed)) & ~TAG_WIDTH'(7)) | TAG_WIDTH'(t);
        epoch = 0;
        for (int t = 0; t < TAGS; t++)
            for (int s = 0; s < SETS; s++)
                mem[t][s] = mem_line(t, s, epoch);
        for (int w = 0; w < 2; w++)
            for (int i = 0; i < SETS; i++) begin
                m_valid[w][i]  = 1'b0;
                m_lost[w][i]   = 1'b0;
                m_recent[w][i] = 1'b0;
            end
        look          = 1'b0;
        look_addr     = '0;
        look_we       = 1'b0;
        look_wdata    = '0;
        look_wstrb    = '0;
        look_hit      = 1'b0;
        look_way      = 0;
        look_data     = '0;
        req_taken     = 1'b0;
        waiting       = 1'b0;
        wait_line     = '0;
        wait_way      = 0;
        wait_data     = '0;
        mem_count     = 0;
        mem_latency   = 0;
        stored        = 1'b0;
        stored_way    = 0;
        stored_index  = '0;
        rst_n         = 1'b0;
        invalidate    = 1'b0;
        req_valid     = 1'b0;
        req_we        = 1'b0;
        req_addr      = '0;
        req_addr.tag  = pool[0];
        req_wdata     = '0;
        req_wstrb     = '0;
        mem_req_ready = 1'b0;
        mem_rsp_valid = 1'b0;
        mem_rsp_data  = '0;
        // Reset: every line invalid, and no memory request.
        @(negedge clk);
        @(negedge clk);
        if (mem_req_valid !== 1'b0)
            $fatal(1, "SkewedCache %0d: mem_req_valid %b during reset", SETS, mem_req_valid);
        rst_n = 1'b1;
        random_test();
        // Bit 16 load hits in way 0, ... bit 0 latency over 1: a 1 is a case that did not
        // happen.
        missing = {n_load_hit0 == 0, n_load_hit1 == 0, n_hit1_skewed == 0, n_load_miss == 0,
                   n_store_hit == 0, n_store_partial == 0, n_store_miss == 0, n_fwd == 0,
                   n_fwd_ways == 0, n_fwd_index == 0, n_by_recent == 0, n_by_tie == 0,
                   n_store_held == 0, n_read_held == 0, n_lost == 0, n_lat1 == 0,
                   n_lat_more == 0};
        if (missing != '0)
            $fatal(1, "SkewedCache %0d: cases that did not happen (load hit way 0 first): %b",
                   SETS, missing);
        done = 1'b1;
    end
endmodule

module TbSkewedCache;
`ifdef VERILATOR
    localparam bit WIDE = 1'b1;     // also 64 lines per way with 32-bit addresses
`else
    localparam bit WIDE = 1'b0;
`endif
    wire clk;
    wire done_1w;
    wire done_2w;
    wire done_64;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbSkewedCacheCheck #(.SETS_OFFSET(2)) u_check_1w(.clk, .done(done_1w));
    TbSkewedCacheCheck #(.SETS_OFFSET(3)) u_check_2w(.clk, .done(done_2w));
    if (WIDE) begin: g_wide
        TbSkewedCacheCheck #(.ADDR_WIDTH(32), .SETS_WIDTH(6), .SETS_OFFSET(2)) u_check_64(
            .clk, .done(done_64));
    end else begin: g_narrow
        assign done_64 = 1'b1;
    end

    initial begin
        wait (done_1w && done_2w && done_64);
        $display("PASS");
        $finish;
    end
endmodule
