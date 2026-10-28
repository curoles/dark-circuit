/* Test of DirectCacheRdOnly.
 *
 * Random, the way a CPU fetches through the cache: a request in most clocks, held until the
 * cache takes it (the valid/ready rules), to addresses of a few tags per set, so that lines
 * are evicted and come back; a memory that takes a line request in 70 % of the clocks and
 * answers it after 1 to 4 clocks; now and then an invalidate while no miss is served, after
 * which the memory has new content (code was written, then FENCE.I): a line kept valid by
 * mistake answers old data. A model of its own (valid, tag and line per set, the lookup of a
 * miss held while memory does not take its request) checks in every clock req_ready,
 * mem_req_valid with the line address, rsp_valid and rsp_data, against the hit or miss it
 * computes; mem_req_valid must be 0 during reset. In the end the test checks that every
 * case happened: hits, back-to-back hits, misses, misses that evict a line, misses on a
 * line an invalidate cleared, requests that wait for req_ready, a line request that waits
 * for memory, both memory latencies (1 clock, more).
 * Verilator runs two sizes, 64 sets with 32-bit addresses and 8 sets with 12-bit addresses,
 * 20000 clocks each; Icarus, slow on the gates of the struct RAMs, the small size with 2000.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbCacheCheck #(
    parameter ADDR_WIDTH  = 32,
    parameter SETS_WIDTH  = 6,      // up to 8
    parameter SETS_OFFSET = 2
)(
    input  wire  clk,
    output logic done
);
    localparam DATA_WIDTH  = 8 << SETS_OFFSET;
    localparam TAG_WIDTH   = ADDR_WIDTH - SETS_WIDTH - SETS_OFFSET;    // 2 or more
    localparam SETS        = 1 << SETS_WIDTH;
`ifdef VERILATOR
    localparam N_CLOCKS    = 20000;
`else
    localparam N_CLOCKS    = 2000;
`endif
    localparam TAGS        = 3;     // tags of the addresses: lines are evicted and come back
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

    // Model of the cache, 2-state.
    bit                    m_valid  [SETS];
    bit [TAG_WIDTH-1:0]    m_tag    [SETS];
    bit [DATA_WIDTH-1:0]   m_data   [SETS];
    bit                    m_lost   [SETS];     // the line was valid when an invalidate came
    integer                epoch;               // memory content: new after every invalidate

    // What the model expects in this clock.
    logic  look;            // a request taken before is looked up now (or held)
    logic  req_taken;       // the cache took the request at the edge before
    addr_t look_addr;
    logic  look_hit;
    data_t look_data;       // its line, when it hits
    logic  waiting;         // a miss is served
    addr_t wait_line;       // its line address
    integer mem_count;      // clocks until memory answers, 0: no line request in flight
    integer mem_latency;    // latency of the line request in flight

    tag_t   pool [TAGS];
    integer seed;

    // Cases seen.
    integer n_hit;
    integer n_hit_b2b;
    integer n_miss;
    integer n_evict;
    integer n_lost;
    integer n_waited;       // a request waits for req_ready
    integer n_mem_held;     // a line request waits for memory
    integer n_lat1;
    integer n_lat_more;

    DirectCacheRdOnly #(.ADDR_WIDTH(ADDR_WIDTH), .SETS_WIDTH(SETS_WIDTH),
                        .SETS_OFFSET(SETS_OFFSET)) u_direct_cache_rd_only(
        .clk, .rst_n, .invalidate, .req_valid, .req_addr, .req_ready, .rsp_valid, .rsp_data,
        .mem_req_valid, .mem_req_ready, .mem_req_addr, .mem_rsp_valid, .mem_rsp_data);

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
            $fatal(1, "Cache %0d: ready %b mem_req %b %h rsp %b %h, expected %b %b %h %b %h",
                   SETS_WIDTH, req_ready, mem_req_valid, mem_req_addr, rsp_valid, rsp_data,
                   model_ready(), exp_mem_req, line_of(look_addr), exp_rsp, exp_data);
    endtask

    // Model of one rising edge with the inputs of this clock.
    task automatic model_edge;
        logic accept;
        logic held;
        logic was_look_hit;
        set_t s;
        accept       = req_valid && model_ready();
        held         = look && !look_hit && !mem_req_ready;
        was_look_hit = look && look_hit;
        if (req_valid && !model_ready())
            n_waited = n_waited + 1;
        if (held)
            n_mem_held = n_mem_held + 1;
        // The line request of a miss goes to memory when memory takes it; its answer ends the
        // miss.
        if (look && !look_hit && mem_req_ready) begin
            waiting     = 1'b1;
            wait_line   = line_of(look_addr);
            mem_latency = 1 + {$random(seed)} % MAX_LATENCY;
            mem_count   = mem_latency;
        end else if (waiting && mem_rsp_valid) begin
            s           = wait_line.set;
            m_valid[s]  = 1'b1;
            m_tag[s]    = wait_line.tag;
            m_data[s]   = mem_rsp_data;
            m_lost[s]   = 1'b0;
            waiting     = 1'b0;
        end
        // A request is looked up with the lines as they are before this edge; a held lookup
        // stays as it is.
        look      = accept || held;
        req_taken = accept;     // req_valid stays until after the edge
        if (accept) begin
            s         = req_addr.set;
            look_addr = req_addr;
            look_hit  = m_valid[s] && m_tag[s] == req_addr.tag;
            look_data = m_data[s];
            if (look_hit) begin
                n_hit = n_hit + 1;
                if (was_look_hit)
                    n_hit_b2b = n_hit_b2b + 1;
            end else begin
                n_miss = n_miss + 1;
                if (m_valid[s])
                    n_evict = n_evict + 1;
                if (m_lost[s] && m_tag[s] == req_addr.tag)
                    n_lost = n_lost + 1;
            end
        end
        if (invalidate) begin
            for (int i = 0; i < SETS; i++) begin
                m_lost[i]  = m_valid[i];
                m_valid[i] = 1'b0;
            end
            epoch = epoch + 1;
        end
    endtask

    task automatic random_test;
        // Bits of r: 0..2 request, 3..8 invalidate, 9..10 tag, 16 and up offset and set; the
        // rest unused.
        /* verilator lint_off UNUSEDSIGNAL */
        integer r;
        /* verilator lint_on UNUSEDSIGNAL */
        for (int k = 0; k < N_CLOCKS; k++) begin
            r = $random(seed);
            // The CPU holds a request until it is taken (rule 2), then may send the next.
            if (req_taken)
                req_valid = 1'b0;
            if (!req_valid && r[2:0] != 3'b000) begin
                req_valid       = 1'b1;
                req_addr.tag    = pool[r[10:9] % TAGS];
                req_addr.set    = r[16 + SETS_OFFSET +: SETS_WIDTH];
                req_addr.offset = r[16 +: SETS_OFFSET];
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
        done = 1'b0;
        seed = SETS_WIDTH;
        n_hit      = 0;
        n_hit_b2b  = 0;
        n_miss     = 0;
        n_evict    = 0;
        n_lost     = 0;
        n_waited   = 0;
        n_mem_held = 0;
        n_lat1     = 0;
        n_lat_more = 0;
        // Different tags, with random high bits.
        for (int t = 0; t < TAGS; t++)
            pool[t] = (TAG_WIDTH'($random(seed)) & ~TAG_WIDTH'(3)) | TAG_WIDTH'(t);
        epoch         = 0;
        look          = 1'b0;
        req_taken     = 1'b0;
        look_addr     = '0;
        look_hit      = 1'b0;
        look_data     = '0;
        waiting       = 1'b0;
        wait_line     = '0;
        mem_count     = 0;
        mem_latency   = 0;
        rst_n         = 1'b0;
        invalidate    = 1'b0;
        req_valid     = 1'b0;
        req_addr      = '0;
        mem_req_ready = 1'b0;
        mem_rsp_valid = 1'b0;
        mem_rsp_data  = '0;
        // Reset: every line invalid, and no line request (rule 4).
        @(negedge clk);
        @(negedge clk);
        if (mem_req_valid !== 1'b0)
            $fatal(1, "Cache %0d: mem_req_valid %b during reset", SETS_WIDTH, mem_req_valid);
        rst_n = 1'b1;
        random_test();
        if (n_hit == 0 || n_hit_b2b == 0 || n_miss == 0 || n_evict == 0 || n_lost == 0 ||
            n_waited == 0 || n_mem_held == 0 || n_lat1 == 0 || n_lat_more == 0)
            $fatal(1, "Cache %0d: a case did not happen: hit %0d %0d, miss %0d %0d %0d, %s %0d %0d %0d %0d",
                   SETS_WIDTH, n_hit, n_hit_b2b, n_miss, n_evict, n_lost, "waited, held, latency",
                   n_waited, n_mem_held, n_lat1, n_lat_more);
        done = 1'b1;
    end
endmodule

module TbDirectCacheRdOnly;
`ifdef VERILATOR
    localparam bit WIDE = 1'b1;     // also 64 sets with 32-bit addresses
`else
    localparam bit WIDE = 1'b0;
`endif
    wire clk;
    wire done_64;
    wire done_8;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbCacheCheck #(.ADDR_WIDTH(12), .SETS_WIDTH(3), .SETS_OFFSET(2)) u_check_8(
        .clk, .done(done_8));
    if (WIDE) begin: g_wide
        TbCacheCheck #(.ADDR_WIDTH(32), .SETS_WIDTH(6), .SETS_OFFSET(2)) u_check_64(
            .clk, .done(done_64));
    end else begin: g_narrow
        assign done_64 = 1'b1;
    end

    initial begin
        wait (done_64 && done_8);
        $display("PASS");
        $finish;
    end
endmodule
