/* Test of SkidBuffer (behave or struct, through SkidBufferT) and FifoVldRdyT.
 *
 * Chain: source -> SkidBufferT -> FifoVldRdyT -> SkidBufferT -> sink, items of a 17-bit
 * struct, every item different. Phases: full speed (no gaps, ready always), then random
 * gaps and random ready at several rates. Every phase sends N items; the sink must
 * receive them all, once, in order, unchanged, and it checks the valid/ready rules
 * itself (SimVldRdySink). At full speed the chain must move one item per cycle.
 * Stops at the first mismatch with $fatal. Verilator only (type parameters).
 */
module TbSkidBuffer;
    typedef struct packed {
        logic [3:0]  tag;
        logic [11:0] value;
        logic        last;
    } item_t;

    localparam int N       = 2000;            // items per phase
    localparam int LATENCY = 3;               // cycles through the chain at full speed

    wire   clk;
    wire   rst_n;
    wire   a_valid;                           // source -> skid buffer 0
    wire   a_ready;
    item_t a_data;
    wire   b_valid;                           // skid buffer 0 -> FIFO
    wire   b_ready;
    item_t b_data;
    wire   c_valid;                           // FIFO -> skid buffer 1
    wire   c_ready;
    item_t c_data;
    wire   d_valid;                           // skid buffer 1 -> sink
    wire   d_ready;
    item_t d_data;
    // FIFO status outputs are tested by the Fifo test.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [2:0] count;
    wire       almost_full;
    wire       almost_empty;
    /* verilator lint_on UNUSEDSIGNAL */
    int    cycle;
    int    base;                              // items sent in earlier phases

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    SimVldRdySource #(.T(item_t)) u_sim_vld_rdy_source(
        .clk, .rst_n, .out_valid(a_valid), .out_ready(a_ready), .out_data(a_data));

    SkidBufferT #(.T(item_t)) u_skid_buffer_t_0(
        .clk, .rst_n, .in_valid(a_valid), .in_ready(a_ready), .in_data(a_data),
        .out_valid(b_valid), .out_ready(b_ready), .out_data(b_data));

    FifoVldRdyT #(.T(item_t), .ADDR_WIDTH(2)) u_fifo_vld_rdy_t(
        .clk, .rst_n, .in_valid(b_valid), .in_ready(b_ready), .in_data(b_data),
        .out_valid(c_valid), .out_ready(c_ready), .out_data(c_data),
        .count, .almost_full, .almost_empty);

    SkidBufferT #(.T(item_t)) u_skid_buffer_t_1(
        .clk, .rst_n, .in_valid(c_valid), .in_ready(c_ready), .in_data(c_data),
        .out_valid(d_valid), .out_ready(d_ready), .out_data(d_data));

    SimVldRdySink #(.T(item_t)) u_sim_vld_rdy_sink(
        .clk, .rst_n, .in_valid(d_valid), .in_ready(d_ready), .in_data(d_data));

    always @(posedge clk)
        cycle <= cycle + 1;

    // Item number i: tag and value are the 16 low bits of i, last its parity.
    function automatic item_t item(input int i);
        return '{tag: i[3:0], value: i[15:4], last: ^i};
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
                $fatal(1, "TbSkidBuffer %s: %0d of %0d items after %0d cycles", name,
                       u_sim_vld_rdy_sink.received.size(), N, cycle - start);
        end
        cycles = cycle - start;
        if (gap_pct == 0 && ready_pct == 100 && cycles > N + LATENCY + 2)
            $fatal(1, "TbSkidBuffer %s: %0d cycles for %0d items, expected one item per cycle",
                   name, cycles, N);
        repeat (20) @(posedge clk);           // no item may come twice
        if (u_sim_vld_rdy_sink.received.size() != N)
            $fatal(1, "TbSkidBuffer %s: %0d items received, sent %0d", name,
                   u_sim_vld_rdy_sink.received.size(), N);
        for (int i = 0; i < N; i++)
            if (u_sim_vld_rdy_sink.received[i] !== item(base + i))
                $fatal(1, "TbSkidBuffer %s: item %0d is %h, expected %h", name, i,
                       u_sim_vld_rdy_sink.received[i], item(base + i));
        $display("TbSkidBuffer %s: %0d items in %0d cycles", name, N, cycles);
        base += N;
    endtask

    initial begin
        cycle = 0;
        base  = 0;
        @(posedge rst_n);
        run(0,  100, "full speed");
        run(30, 100, "gaps");
        run(0,  40,  "slow sink");
        run(50, 50,  "both random");
        run(10, 90,  "mostly fast");
        $finish;
    end

endmodule
