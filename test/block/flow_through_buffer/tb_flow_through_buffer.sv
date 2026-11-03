/* Test of FlowThroughBuffer (behave or struct, through FlowThroughBufferT).
 *
 * Chain: source -> buffer 0 -> buffer 1 -> sink, every item different. Phases: full speed (no
 * gaps, ready always), then random gaps and random ready at several rates. Every phase sends
 * N items; the sink must receive them all, once, in order, unchanged, and it checks the
 * valid/ready rules itself (SimVldRdySink). The pattern itself: while both buffers are empty,
 * the source's item is at the sink in the same clock (it flows through, no added clock), so
 * at full speed the chain moves one item per clock with no latency. A probe buffer driven by
 * the testbench shows the rest: an item not taken stays in the entry and is offered until
 * taken; in_ready is a flip-flop (out_ready changed within a clock does not change it, and it
 * stays 0 in the clock the held item leaves); then the next item flows through again.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbFlowThroughBuffer;
    typedef logic [16:0] item_t;

`ifdef VERILATOR
    localparam int N = 2000;                  // items per phase
`else
    localparam int N = 300;
`endif

    wire   clk;
    wire   rst_n;
    wire   a_valid;                           // source -> buffer 0
    wire   a_ready;
    item_t a_data;
    wire   b_valid;                           // buffer 0 -> buffer 1
    wire   b_ready;
    item_t b_data;
    wire   c_valid;                           // buffer 1 -> sink
    wire   c_ready;
    item_t c_data;
    // The probe buffer, driven by the testbench.
    logic  p_in_valid;
    wire   p_in_ready;
    item_t p_in_data;
    wire   p_out_valid;
    logic  p_out_ready;
    item_t p_out_data;
    int    cycle;
    int    base;                              // items sent in earlier phases
    int    n_flow;                            // clocks an item flowed through both buffers

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    SimVldRdySource #(.T(item_t)) u_sim_vld_rdy_source(
        .clk, .rst_n, .out_valid(a_valid), .out_ready(a_ready), .out_data(a_data));

    FlowThroughBufferT #(.T(item_t)) u_flow_0(
        .clk, .rst_n, .in_valid(a_valid), .in_ready(a_ready), .in_data(a_data),
        .out_valid(b_valid), .out_ready(b_ready), .out_data(b_data));

    FlowThroughBufferT #(.T(item_t)) u_flow_1(
        .clk, .rst_n, .in_valid(b_valid), .in_ready(b_ready), .in_data(b_data),
        .out_valid(c_valid), .out_ready(c_ready), .out_data(c_data));

    SimVldRdySink #(.T(item_t)) u_sim_vld_rdy_sink(
        .clk, .rst_n, .in_valid(c_valid), .in_ready(c_ready), .in_data(c_data));

    FlowThroughBufferT #(.T(item_t)) u_flow_probe(
        .clk, .rst_n, .in_valid(p_in_valid), .in_ready(p_in_ready), .in_data(p_in_data),
        .out_valid(p_out_valid), .out_ready(p_out_ready), .out_data(p_out_data));

    always @(posedge clk)
        cycle <= cycle + 1;

    // Both buffers empty (each one's in_ready): the source's offer is the sink's, in the same
    // clock. Checked before the edge.
    always @(negedge clk)
        if (rst_n && a_ready && b_ready) begin
            if (c_valid !== a_valid || (a_valid && c_data !== a_data))
                $fatal(1, "TbFlowThroughBuffer: both empty, source %b %h, sink sees %b %h",
                       a_valid, a_data, c_valid, c_data);
            if (a_valid)
                n_flow <= n_flow + 1;
        end

    // Item number i: its 17 low bits, every item of a run different.
    function automatic item_t item(input int i);
        return item_t'(i * 7 + 3);
    endfunction

    // Send N items with the given rates; all must arrive in order, unchanged, once.
    task automatic run(input int gap_pct, input int ready_pct, input string name);
        int start;
        int cycles;                           // until the last item arrived
        u_sim_vld_rdy_source.gap_pct = gap_pct;
        u_sim_vld_rdy_sink.ready_pct = ready_pct;
        u_sim_vld_rdy_sink.received.delete();
        for (int i = 0; i < N; i++)
            u_sim_vld_rdy_source.push(item(base + i));
        start = cycle;
        while (u_sim_vld_rdy_sink.received.size() < N) begin
            @(posedge clk);
            if (cycle - start > 100 * N)
                $fatal(1, "TbFlowThroughBuffer %s: %0d of %0d items after %0d cycles", name,
                       u_sim_vld_rdy_sink.received.size(), N, cycle - start);
        end
        cycles = cycle - start;
        if (gap_pct == 0 && ready_pct == 100 && cycles > N + 2)
            $fatal(1, "TbFlowThroughBuffer %s: %0d cycles for %0d items, expected one per cycle",
                   name, cycles, N);
        repeat (20) @(posedge clk);           // no item may come twice
        if (u_sim_vld_rdy_sink.received.size() != N)
            $fatal(1, "TbFlowThroughBuffer %s: %0d items received, sent %0d", name,
                   u_sim_vld_rdy_sink.received.size(), N);
        for (int i = 0; i < N; i++)
            if (u_sim_vld_rdy_sink.received[i] !== item(base + i))
                $fatal(1, "TbFlowThroughBuffer %s: item %0d is %h, expected %h", name, i,
                       u_sim_vld_rdy_sink.received[i], item(base + i));
        $display("TbFlowThroughBuffer %s: %0d items in %0d cycles", name, N, cycles);
        base += N;
    endtask

    // The probe's outputs now against the expected ones.
    task automatic expect_probe(input logic in_ready, input logic out_valid, input item_t out_data,
                                input string step);
        if (p_in_ready !== in_ready || p_out_valid !== out_valid ||
            (out_valid && p_out_data !== out_data))
            $fatal(1, "TbFlowThroughBuffer probe, %s: in_ready %b out_valid %b out_data %h, expected %b %b %h",
                   step, p_in_ready, p_out_valid, p_out_data, in_ready, out_valid, out_data);
    endtask

    // Inputs change after the falling edge, outputs are checked a moment later.
    task automatic probe;
        @(negedge clk);
        p_in_valid = 1'b1; p_in_data = 17'h1aaaa; p_out_ready = 1'b1;
        #1 expect_probe(1'b1, 1'b1, 17'h1aaaa, "empty: the item flows through");
        p_out_ready = 1'b0;
        #1 expect_probe(1'b1, 1'b1, 17'h1aaaa, "out_ready falls: in_ready stays 1");
        @(negedge clk);                       // not taken: in the entry
        p_in_data = 17'h05555;
        #1 expect_probe(1'b0, 1'b1, 17'h1aaaa, "full: the held item, not in's");
        p_out_ready = 1'b1;
        #1 expect_probe(1'b0, 1'b1, 17'h1aaaa, "out_ready rises: in_ready stays 0");
        @(negedge clk);                       // the held item left; in's was not taken
        #1 expect_probe(1'b1, 1'b1, 17'h05555, "empty again: the next item flows through");
        @(negedge clk);                       // taken at once
        p_in_valid = 1'b0;
        #1 expect_probe(1'b1, 1'b0, 17'h00000, "nothing offered");
    endtask

    initial begin
        cycle       = 0;
        base        = 0;
        n_flow      = 0;
        p_in_valid  = 1'b0;
        p_in_data   = '0;
        p_out_ready = 1'b0;
        @(posedge rst_n);
        probe();
        run(0,  100, "full speed");
        run(30, 100, "gaps");
        run(0,  40,  "slow sink");
        run(50, 50,  "both random");
        run(10, 90,  "mostly fast");
        if (n_flow < N)
            $fatal(1, "TbFlowThroughBuffer: an item flowed through both buffers %0d times", n_flow);
        $display("PASS");
        $finish;
    end

endmodule
