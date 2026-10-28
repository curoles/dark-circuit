/* Test of SetAssocCacheRdOnly.
 *
 * Random, the way a CPU fetches through the cache: requests in most clocks, also while
 * req_ready=0 (they must be ignored), to addresses of WAYS + 1 tags per set, so that lines
 * are evicted and come back, often to the set of the request before (back-to-back requests
 * to one set, where the replacement state is forwarded); a memory that answers each line
 * request after 1 to 4 clocks; now and then an invalidate while no miss is served, after
 * which the memory has new content (a line kept valid by mistake answers old data). A model
 * of its own (valid, tag, line and time of the last touch per way) checks in every clock
 * req_ready, mem_req_en with the line address, rsp_valid and rsp_data, against the hit or
 * miss it computes; its victim is the lowest invalid way of the set as read with the
 * request, else the way touched longest ago (REPL_LRU) or the low bits of an Lfsr like the
 * cache's, reset with it (REPL_RANDOM): so the model knows every line the cache keeps. In
 * the end the test checks that every case happened: hits, back-to-back hits, back-to-back
 * hits of two ways of one set, misses, misses that evict a line, misses on a line an
 * invalidate cleared, ignored requests, both memory latencies.
 * Verilator runs 2, 3 and 4 ways with LRU and 4 ways random on 8 sets with 12-bit addresses
 * and 4 ways with LRU on 64 sets with 32-bit addresses, 20000 clocks each; Icarus 2 and 4
 * ways with LRU and 4 ways random on 8 sets, 600 clocks (the struct version is slow
 * there). Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbSetAssocCacheCheck import CachePkg::*; #(
    parameter ADDR_WIDTH  = 12,
    parameter SETS_WIDTH  = 3,      // up to 8
    parameter SETS_OFFSET = 2,
    parameter WAYS        = 4,
    parameter REPLACEMENT = REPL_LRU
)(
    input  wire  clk,
    output logic done
);
    localparam DATA_WIDTH  = 8 << SETS_OFFSET;
    localparam TAG_WIDTH   = ADDR_WIDTH - SETS_WIDTH - SETS_OFFSET;    // 3 or more
    localparam SETS        = 1 << SETS_WIDTH;
    localparam WW          = $clog2(WAYS);
`ifdef VERILATOR
    localparam N_CLOCKS    = 20000;
`else
    localparam N_CLOCKS    = 600;   // about 1 s at most for a library test (struct)
`endif
    localparam TAGS        = WAYS + 1;  // tags of the addresses: lines are evicted, come back
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
    logic  req_en;
    addr_t req_addr;
    wire   req_ready;
    wire   rsp_valid;
    data_t rsp_data;
    wire   mem_req_en;
    addr_t mem_req_addr;
    logic  mem_rsp_valid;
    data_t mem_rsp_data;
    // The random policy's Lfsr, a copy of the cache's: the model knows every random victim.
    // Only the low bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0] lfsr_q;
    /* verilator lint_on UNUSEDSIGNAL */

    // Model of the cache, 2-state.
    bit                  m_valid [SETS][WAYS];
    bit [TAG_WIDTH-1:0]  m_tag   [SETS][WAYS];
    bit [DATA_WIDTH-1:0] m_data  [SETS][WAYS];
    bit                  m_lost  [SETS][WAYS];  // the line was valid when an invalidate came
    integer              m_stamp [SETS][WAYS];  // time of the last touch
    integer              now;
    integer              epoch;                 // memory content: new after every invalidate

    // What the model expects in this clock.
    logic   look;           // the request of the clock before is looked up now
    addr_t  look_addr;
    logic   look_hit;
    integer look_way;       // its way, when it hits
    data_t  look_data;      // its line, when it hits
    bit     look_valid [WAYS];  // valid bits of its set as read with the request
    logic   waiting;        // a miss is served
    addr_t  wait_line;      // its line address
    // An index below WAYS: its high bits are always 0.
    /* verilator lint_off UNUSEDSIGNAL */
    integer wait_way;       // the way its line goes into
    /* verilator lint_on UNUSEDSIGNAL */
    integer mem_count;      // clocks until memory answers, 0: no line request in flight
    integer mem_latency;    // latency of the line request in flight
    set_t   last_set;       // set of the last request
    logic   last_touch;     // the clock before touched a way by a hit
    set_t   last_touch_set;
    integer last_touch_way;

    tag_t   pool [TAGS];
    integer seed;

    // Cases seen.
    integer n_hit;
    integer n_hit_b2b;
    integer n_hit_b2b_ways;     // back-to-back hits of two ways of one set (forwarding)
    integer n_miss;
    integer n_evict;
    integer n_lost;
    integer n_ignored;
    integer n_lat1;
    integer n_lat_more;

    SetAssocCacheRdOnly #(.ADDR_WIDTH(ADDR_WIDTH), .SETS_WIDTH(SETS_WIDTH),
                          .SETS_OFFSET(SETS_OFFSET), .WAYS(WAYS), .REPLACEMENT(REPLACEMENT))
        u_set_assoc_cache_rd_only(
            .clk, .rst_n, .invalidate, .req_en, .req_addr, .req_ready, .rsp_valid, .rsp_data,
            .mem_req_en, .mem_req_addr, .mem_rsp_valid, .mem_rsp_data);

    Lfsr #(.WIDTH(8)) u_lfsr(.clk, .rst_n, .q(lfsr_q));

    // The address of the line of a: offset 0.
    function automatic addr_t line_of(input addr_t a);
        addr_t l;
        l        = a;
        l.offset = '0;
        return l;
    endfunction

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

    // The way a miss of set s replaces: the lowest invalid way as read with the request,
    // else the policy's way.
    function automatic integer model_victim(input set_t s);
        integer k;
        for (int w = 0; w < WAYS; w++)
            if (!look_valid[w])
                return w;
        if (REPLACEMENT == REPL_RANDOM)
            return int'(lfsr_q[WW-1:0]);
        k = 0;
        for (int w = 1; w < WAYS; w++)
            if (m_stamp[s][w] < m_stamp[s][k])
                k = w;
        return k;
    endfunction

    // After the inputs of this clock settled: the outputs are those of the model.
    task automatic check;
        logic  exp_mem_req;
        logic  exp_rsp;
        data_t exp_data;
        exp_mem_req = look && !look_hit;
        exp_rsp     = (look && look_hit) || (waiting && mem_rsp_valid);
        exp_data    = waiting ? mem_rsp_data : look_data;
        if (req_ready !== model_ready() || mem_req_en !== exp_mem_req ||
            (exp_mem_req && mem_req_addr !== line_of(look_addr)) || rsp_valid !== exp_rsp ||
            (exp_rsp && rsp_data !== exp_data))
            $fatal(1, "Cache %0d ways %0d: ready %b mem_req %b %h rsp %b %h, expected %b %b %h %b %h",
                   WAYS, REPLACEMENT, req_ready, mem_req_en, mem_req_addr, rsp_valid,
                   rsp_data, model_ready(), exp_mem_req, line_of(look_addr), exp_rsp, exp_data);
    endtask

    // Model of one rising edge with the inputs of this clock.
    task automatic model_edge;
        logic accept;
        logic was_look_hit;
        logic all_valid;
        set_t s;
        accept       = req_en && model_ready();
        was_look_hit = look && look_hit;
        if (req_en && !model_ready())
            n_ignored = n_ignored + 1;
        // The lookup of this clock: a hit touches its way; a miss takes its victim now and
        // sends the line request to memory; the memory's answer fills the way.
        last_touch = 1'b0;
        if (look && look_hit) begin
            s                    = look_addr.set;
            now                  = now + 1;
            m_stamp[s][look_way] = now;
            last_touch           = 1'b1;
            last_touch_set       = s;
            last_touch_way       = look_way;
        end else if (look && !look_hit) begin
            waiting     = 1'b1;
            wait_line   = line_of(look_addr);
            wait_way    = model_victim(look_addr.set);
            mem_latency = 1 + {$random(seed)} % MAX_LATENCY;
            mem_count   = mem_latency;
        end else if (waiting && mem_rsp_valid) begin
            s                    = wait_line.set;
            m_valid[s][wait_way] = 1'b1;
            m_tag[s][wait_way]   = wait_line.tag;
            m_data[s][wait_way]  = mem_rsp_data;
            m_lost[s][wait_way]  = 1'b0;
            now                  = now + 1;
            m_stamp[s][wait_way] = now;
            waiting              = 1'b0;
        end
        // A request is looked up with the lines as they are before this edge.
        look = accept;
        if (accept) begin
            s         = req_addr.set;
            look_addr = req_addr;
            look_hit  = 1'b0;
            for (int w = 0; w < WAYS; w++) begin
                look_valid[w] = m_valid[s][w];
                if (m_valid[s][w] && m_tag[s][w] == req_addr.tag) begin
                    look_hit  = 1'b1;
                    look_way  = w;
                    look_data = m_data[s][w];
                end
            end
            if (look_hit) begin
                n_hit = n_hit + 1;
                if (was_look_hit)
                    n_hit_b2b = n_hit_b2b + 1;
                if (last_touch && last_touch_set == s && last_touch_way != look_way)
                    n_hit_b2b_ways = n_hit_b2b_ways + 1;
            end else begin
                n_miss = n_miss + 1;
                all_valid = 1'b1;
                for (int w = 0; w < WAYS; w++) begin
                    if (m_lost[s][w] && m_tag[s][w] == req_addr.tag)
                        n_lost = n_lost + 1;
                    all_valid = all_valid && look_valid[w];
                end
                if (all_valid)
                    n_evict = n_evict + 1;
            end
        end
        if (invalidate) begin
            for (int i = 0; i < SETS; i++)
                for (int w = 0; w < WAYS; w++) begin
                    m_lost[i][w]  = m_valid[i][w];
                    m_valid[i][w] = 1'b0;
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
            r               = $random(seed);
            req_en          = r[2:0] != 3'b000;
            req_addr.tag    = pool[r[11:9] % TAGS];
            req_addr.set    = r[13:12] == 2'b00 ? r[16 + SETS_OFFSET +: SETS_WIDTH] : last_set;
            req_addr.offset = r[16 +: SETS_OFFSET];
            if (req_en && model_ready())
                last_set = req_addr.set;
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
        req_en        = 1'b0;
        invalidate    = 1'b0;
        mem_rsp_valid = 1'b0;
    endtask

    initial begin
        done           = 1'b0;
        seed           = SETS_WIDTH * 16 + WAYS * 2 + REPLACEMENT;
        n_hit          = 0;
        n_hit_b2b      = 0;
        n_hit_b2b_ways = 0;
        n_miss         = 0;
        n_evict        = 0;
        n_lost         = 0;
        n_ignored      = 0;
        n_lat1         = 0;
        n_lat_more     = 0;
        // Different tags, with random high bits.
        for (int t = 0; t < TAGS; t++)
            pool[t] = (TAG_WIDTH'($random(seed)) & ~TAG_WIDTH'(7)) | TAG_WIDTH'(t);
        for (int i = 0; i < SETS; i++)
            for (int w = 0; w < WAYS; w++) begin
                m_valid[i][w] = 1'b0;
                m_lost[i][w]  = 1'b0;
                m_stamp[i][w] = 0;
            end
        now            = 0;
        epoch          = 0;
        look           = 1'b0;
        look_addr      = '0;
        look_hit       = 1'b0;
        look_way       = 0;
        look_data      = '0;
        waiting        = 1'b0;
        wait_line      = '0;
        wait_way       = 0;
        mem_count      = 0;
        mem_latency    = 0;
        last_set       = '0;
        last_touch     = 1'b0;
        last_touch_set = '0;
        last_touch_way = 0;
        rst_n          = 1'b0;
        invalidate     = 1'b0;
        req_en         = 1'b0;
        req_addr       = '0;
        mem_rsp_valid  = 1'b0;
        mem_rsp_data   = '0;
        // Reset: every line invalid.
        @(negedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        random_test();
        if (n_hit == 0 || n_hit_b2b == 0 || n_hit_b2b_ways == 0 || n_miss == 0 ||
            n_evict == 0 || n_lost == 0 || n_ignored == 0 || n_lat1 == 0 || n_lat_more == 0)
            $fatal(1, "Cache %0d ways %0d: a case did not happen: hit %0d %0d %0d, miss %0d %0d %0d, %s %0d %0d %0d",
                   WAYS, REPLACEMENT, n_hit, n_hit_b2b, n_hit_b2b_ways, n_miss, n_evict, n_lost,
                   "ignored, latency", n_ignored, n_lat1, n_lat_more);
        done = 1'b1;
    end
endmodule

module TbSetAssocCacheRdOnly import CachePkg::*;;
`ifdef VERILATOR
    localparam bit WIDE = 1'b1;     // also 3 ways, and 64 sets with 32-bit addresses
`else
    localparam bit WIDE = 1'b0;
`endif
    wire clk;
    wire done_2;
    wire done_3;
    wire done_4;
    wire done_4r;
    wire done_64;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbSetAssocCacheCheck #(.WAYS(2), .REPLACEMENT(REPL_LRU)) u_check_2(.clk, .done(done_2));
    TbSetAssocCacheCheck #(.WAYS(4), .REPLACEMENT(REPL_LRU)) u_check_4(.clk, .done(done_4));
    TbSetAssocCacheCheck #(.WAYS(4), .REPLACEMENT(REPL_RANDOM)) u_check_4r(
        .clk, .done(done_4r));
    if (WIDE) begin: g_wide
        TbSetAssocCacheCheck #(.WAYS(3), .REPLACEMENT(REPL_LRU)) u_check_3(
            .clk, .done(done_3));
        TbSetAssocCacheCheck #(.ADDR_WIDTH(32), .SETS_WIDTH(6), .WAYS(4),
                               .REPLACEMENT(REPL_LRU)) u_check_64(.clk, .done(done_64));
    end else begin: g_narrow
        assign done_3  = 1'b1;
        assign done_64 = 1'b1;
    end

    initial begin
        wait (done_2 && done_3 && done_4 && done_4r && done_64);
        $display("PASS");
        $finish;
    end
endmodule
