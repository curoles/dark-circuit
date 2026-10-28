/* Test of DirectCache.
 *
 * Random, the way a CPU loads and stores through the cache: a request in most clocks, a
 * third of them stores with random bytes and strobes, held until the cache takes it (the
 * valid/ready rules), to addresses of a few tags per set, often the line or set of the
 * request before (a load right after a store of the same set: forwarding); a memory that
 * takes a request in 70 % of the clocks, keeps the lines (a model of its own, changed by
 * the stores it takes) and answers each read after 1 to 4 clocks; now and then an
 * invalidate while no load miss is served, after which the memory has new content (another
 * writer, then the cache invalidated). A model of the cache (valid, tag and line per set,
 * the lookup held while memory does not take its request) checks in every clock req_ready,
 * mem_req_valid with the fields of the request, rsp_valid and rsp_data; mem_req_valid must
 * be 0 during reset. In the end the test checks that every case happened: load hits and
 * misses, store hits (also with only some bytes) and misses, a load hit right after a store
 * hit of the same set, a store and a read held by memory, evictions, a miss on a line an
 * invalidate cleared, both memory latencies.
 * Lines of one word and of two words (8 strobes) on 8 sets with 12-bit addresses, and, on
 * Verilator only, 64 sets with 32-bit addresses; 20000 clocks on Verilator, 2000 on Icarus.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbDirectCacheCheck #(
    parameter ADDR_WIDTH  = 12,
    parameter SETS_WIDTH  = 3,      // up to 8
    parameter SETS_OFFSET = 2
)(
    input  wire  clk,
    output logic done
);
    localparam DATA_WIDTH  = 8 << SETS_OFFSET;
    localparam STRB_WIDTH  = 1 << SETS_OFFSET;
    localparam TAG_WIDTH   = ADDR_WIDTH - SETS_WIDTH - SETS_OFFSET;    // 2 or more
    localparam SETS        = 1 << SETS_WIDTH;
`ifdef VERILATOR
    localparam N_CLOCKS    = 20000;
`else
    localparam N_CLOCKS    = 2000;
`endif
    localparam TAGS        = 3;     // tags of the addresses: lines are evicted and come back
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

    // Model of the cache, 2-state.
    bit                  m_valid [SETS];
    bit [TAG_WIDTH-1:0]  m_tag   [SETS];
    bit [DATA_WIDTH-1:0] m_data  [SETS];
    bit                  m_lost  [SETS];        // the line was valid when an invalidate came

    // What the model expects in this clock.
    logic   look;           // a request taken before is looked up now (or held)
    addr_t  look_addr;
    logic   look_we;
    data_t  look_wdata;
    strb_t  look_wstrb;
    logic   look_hit;
    data_t  look_data;      // its line, when it hits
    logic   req_taken;      // the cache took the request at the edge before
    logic   waiting;        // a load miss is served
    tag_t   wait_tag;       // its line
    set_t   wait_set;
    data_t  wait_data;      // the line memory answers with
    integer mem_count;      // clocks until memory answers, 0: no read in flight
    integer mem_latency;    // latency of the read in flight
    logic   stored;         // at this edge, a store that hits is taken by memory
    set_t   stored_set;

    tag_t   pool [TAGS];
    integer seed;

    // Cases seen.
    integer n_load_hit;
    integer n_load_miss;
    integer n_store_hit;
    integer n_store_partial;    // a store hit with only some bytes
    integer n_store_miss;
    integer n_fwd;              // a load hit right after a store hit of the same set
    integer n_store_held;
    integer n_read_held;
    integer n_evict;
    integer n_lost;
    integer n_lat1;
    integer n_lat_more;

    DirectCache #(.ADDR_WIDTH(ADDR_WIDTH), .SETS_WIDTH(SETS_WIDTH),
                  .SETS_OFFSET(SETS_OFFSET)) u_direct_cache(
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

    // Index of a tag in the pool (the tags of every address the test uses).
    function automatic integer tag_index(input tag_t t);
        for (int i = 0; i < TAGS; i++)
            if (pool[i] == t)
                return i;
        $fatal(1, "DirectCache %0d: tag %h is not in the pool", SETS_OFFSET, t);
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

    // After the inputs of this clock settled: the outputs are those of the model.
    task automatic check;
        logic  exp_rsp;
        data_t exp_data;
        exp_rsp  = (look && !look_we && look_hit) || (waiting && mem_rsp_valid);
        exp_data = waiting ? mem_rsp_data : look_data;
        if (req_ready !== exp_ready() || mem_req_valid !== exp_mem_valid() ||
            rsp_valid !== exp_rsp || (exp_rsp && rsp_data !== exp_data))
            $fatal(1, "DirectCache %0d: ready %b mem_req %b rsp %b %h, expected %b %b %b %h",
                   SETS_OFFSET, req_ready, mem_req_valid, rsp_valid, rsp_data, exp_ready(),
                   exp_mem_valid(), exp_rsp, exp_data);
        if (exp_mem_valid() &&
            (mem_req_we !== look_we || mem_req_addr !== line_of(look_addr) ||
             (look_we && (mem_req_wdata !== look_wdata || mem_req_wstrb !== look_wstrb))))
            $fatal(1, "DirectCache %0d: mem_req we %b %h %h %b, expected %b %h %h %b",
                   SETS_OFFSET, mem_req_we, mem_req_addr, mem_req_wdata, mem_req_wstrb,
                   look_we, line_of(look_addr), look_wdata, look_wstrb);
    endtask

    // Model of one rising edge with the inputs of this clock.
    task automatic model_edge;
        logic   taken;          // memory takes the lookup's request
        logic   accept;
        logic   held;
        set_t   s;
        taken  = exp_mem_valid() && mem_req_ready;
        held   = exp_mem_valid() && !mem_req_ready;
        accept = req_valid && exp_ready();
        stored = 1'b0;
        if (held) begin
            if (look_we) n_store_held = n_store_held + 1;
            else         n_read_held  = n_read_held + 1;
        end
        // The lookup's request taken by memory: a store writes memory, and the cache when it
        // hits; a load miss starts its read. The memory's answer fills the line.
        if (taken && look_we) begin
            s = look_addr.set;
            mem[tag_index(look_addr.tag)][s] = merge(mem[tag_index(look_addr.tag)][s],
                                                     look_wdata, look_wstrb);
            if (look_hit) begin
                m_data[s]  = merge(m_data[s], look_wdata, look_wstrb);
                stored     = 1'b1;
                stored_set = s;
                n_store_hit = n_store_hit + 1;
                if (look_wstrb != '1)
                    n_store_partial = n_store_partial + 1;
            end else
                n_store_miss = n_store_miss + 1;
        end else if (taken) begin
            waiting     = 1'b1;
            wait_tag    = look_addr.tag;
            wait_set    = look_addr.set;
            wait_data   = mem[tag_index(look_addr.tag)][look_addr.set];
            mem_latency = 1 + {$random(seed)} % MAX_LATENCY;
            mem_count   = mem_latency;
        end else if (waiting && mem_rsp_valid) begin
            s          = wait_set;
            m_valid[s] = 1'b1;
            m_tag[s]   = wait_tag;
            m_data[s]  = mem_rsp_data;
            m_lost[s]  = 1'b0;
            waiting    = 1'b0;
        end
        // A request is looked up with the lines after this edge's store (forwarding); a held
        // lookup stays as it is.
        if (accept) begin
            s          = req_addr.set;
            look_addr  = req_addr;
            look_we    = req_we;
            look_wdata = req_wdata;
            look_wstrb = req_wstrb;
            look_hit   = m_valid[s] && m_tag[s] == req_addr.tag;
            look_data  = m_data[s];
            if (!req_we && look_hit) begin
                n_load_hit = n_load_hit + 1;
                if (stored && stored_set == s)
                    n_fwd = n_fwd + 1;
            end else if (!req_we) begin
                n_load_miss = n_load_miss + 1;
                if (m_valid[s])
                    n_evict = n_evict + 1;
                if (m_lost[s] && m_tag[s] == req_addr.tag)
                    n_lost = n_lost + 1;
            end
        end
        req_taken = accept;     // req_valid stays until after the edge
        look = accept || held;
        if (invalidate) begin
            for (int i = 0; i < SETS; i++) begin
                m_lost[i]  = m_valid[i];
                m_valid[i] = 1'b0;
            end
            epoch = epoch + 1;
            for (int ti = 0; ti < TAGS; ti++)
                for (int si = 0; si < SETS; si++)
                    mem[ti][si] = mem_line(ti, si, epoch);
        end
    endtask

    // A new request, often to the line or the set of the one before.
    task automatic new_request;
        // Bits of r: 0..1 store, 2..3 same line, 4..5 same set, 6..7 tag, 8..9 all bytes,
        // 16 and up offset and set; the rest unused.
        /* verilator lint_off UNUSEDSIGNAL */
        integer r;
        /* verilator lint_on UNUSEDSIGNAL */
        r      = $random(seed);
        req_we = r[1:0] == 2'b00 || r[1:0] == 2'b01 && r[16];
        if (r[3:2] != 2'b00) begin
            req_addr.tag = pool[r[7:6] % TAGS];
            req_addr.set = r[5:4] == 2'b00 ? r[16 + SETS_OFFSET +: SETS_WIDTH] : req_addr.set;
        end
        req_addr.offset = r[16 +: SETS_OFFSET];
        for (int i = 0; i < DATA_WIDTH / 32; i++)
            req_wdata[32*i +: 32] = $random(seed);
        req_wstrb = STRB_WIDTH'($random(seed));
        if (r[9:8] == 2'b00 || req_wstrb == '0)
            req_wstrb = '1;
        req_valid = 1'b1;
    endtask

    task automatic random_test;
        for (int k = 0; k < N_CLOCKS; k++) begin
            // The CPU holds a request until it is taken (rule 2), then may send the next.
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
        seed            = SETS_WIDTH * 8 + SETS_OFFSET;
        n_load_hit      = 0;
        n_load_miss     = 0;
        n_store_hit     = 0;
        n_store_partial = 0;
        n_store_miss    = 0;
        n_fwd           = 0;
        n_store_held    = 0;
        n_read_held     = 0;
        n_evict         = 0;
        n_lost          = 0;
        n_lat1          = 0;
        n_lat_more      = 0;
        // Different tags, with random high bits.
        for (int t = 0; t < TAGS; t++)
            pool[t] = (TAG_WIDTH'($random(seed)) & ~TAG_WIDTH'(3)) | TAG_WIDTH'(t);
        epoch = 0;
        for (int t = 0; t < TAGS; t++)
            for (int s = 0; s < SETS; s++)
                mem[t][s] = mem_line(t, s, epoch);
        for (int s = 0; s < SETS; s++) begin
            m_valid[s] = 1'b0;
            m_lost[s]  = 1'b0;
        end
        look          = 1'b0;
        look_addr     = '0;
        look_we       = 1'b0;
        look_wdata    = '0;
        look_wstrb    = '0;
        look_hit      = 1'b0;
        look_data     = '0;
        req_taken     = 1'b0;
        waiting       = 1'b0;
        wait_tag      = '0;
        wait_set      = '0;
        wait_data     = '0;
        mem_count     = 0;
        mem_latency   = 0;
        stored        = 1'b0;
        stored_set    = '0;
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
        // Reset: every line invalid, and no memory request (rule 4).
        @(negedge clk);
        @(negedge clk);
        if (mem_req_valid !== 1'b0)
            $fatal(1, "DirectCache %0d: mem_req_valid %b during reset", SETS_OFFSET,
                   mem_req_valid);
        rst_n = 1'b1;
        random_test();
        if (n_load_hit == 0 || n_load_miss == 0 || n_store_hit == 0 || n_store_partial == 0 ||
            n_store_miss == 0 || n_fwd == 0 || n_store_held == 0 || n_read_held == 0 ||
            n_evict == 0 || n_lost == 0 || n_lat1 == 0 || n_lat_more == 0)
            $fatal(1, "DirectCache %0d: a case did not happen: load %0d %0d, store %0d %0d %0d, fwd %0d, held %0d %0d, %s %0d %0d %0d %0d",
                   SETS_OFFSET, n_load_hit, n_load_miss, n_store_hit, n_store_partial,
                   n_store_miss, n_fwd, n_store_held, n_read_held, "evict, lost, latency",
                   n_evict, n_lost, n_lat1, n_lat_more);
        done = 1'b1;
    end
endmodule

module TbDirectCache;
`ifdef VERILATOR
    localparam bit WIDE = 1'b1;     // also 64 sets with 32-bit addresses
`else
    localparam bit WIDE = 1'b0;
`endif
    wire clk;
    wire done_1w;
    wire done_2w;
    wire done_64;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbDirectCacheCheck #(.ADDR_WIDTH(12), .SETS_WIDTH(3), .SETS_OFFSET(2)) u_check_1w(
        .clk, .done(done_1w));
    TbDirectCacheCheck #(.ADDR_WIDTH(12), .SETS_WIDTH(3), .SETS_OFFSET(3)) u_check_2w(
        .clk, .done(done_2w));
    if (WIDE) begin: g_wide
        TbDirectCacheCheck #(.ADDR_WIDTH(32), .SETS_WIDTH(6), .SETS_OFFSET(2)) u_check_64(
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
