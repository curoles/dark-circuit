/* Test of SimLatencyRAM.
 *
 * Random, the way a cache or a core uses it: a request in most clocks, held until it is
 * taken (the valid/ready rules), half of them writes with random bytes and strobes, to a few
 * words, so that a read often follows a write of its word. The memory starts with a file
 * loaded by load() (peek() checks it). A model keeps the bytes (a write changes them when it
 * is taken) and the reads waiting for answers with their words as of when they were taken.
 * In every clock it checks: an answer comes only for a waiting read, the oldest, with its
 * word, at least one clock after it was taken; with MAX_PENDING=1 its latency is in the fast
 * or the slow range; req_ready is 0 while MAX_PENDING reads wait and none answers; in the
 * latency-1 configuration req_ready is always 1 and every answer comes after one clock. In
 * the end the cases of the configuration must have happened: a read taken in the clock a
 * full queue answers, a request stopped by a full queue, ready withheld with a slot free,
 * fast and slow answers, a read of a word just written, a write of some bytes only, two or
 * more reads waiting.
 * Three configurations: latency 1 (READY_PERCENT=100), two-level with one read waiting,
 * two-level with four on words of 8 bytes; 3000 clocks each. Stops at the first mismatch
 * with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbSimLatencyRAMCheck #(
    parameter     DATA_SIZE     = 4,
    parameter     READY_PERCENT = 100,
    parameter     FAST_PERCENT  = 100,
    parameter     FAST_MIN      = 1,
    parameter     FAST_MAX      = 1,
    parameter     SLOW_MIN      = 10,
    parameter     SLOW_MAX      = 20,
    parameter     MAX_PENDING   = 1,
    parameter     SEED          = 1,
    parameter bit EXACT         = 1'b0,     // latency 1, always ready: check that exactly
    parameter     REQUIRED      = 8'hFF     // cases that must happen, bits as in missing
)(
    input  wire  clk,
    output logic done
);
    localparam ADDR_WIDTH = 8;              // 256 bytes
    localparam DATA_WIDTH = 8 * DATA_SIZE;
    localparam AS         = $clog2(DATA_SIZE);
    localparam WORDS      = 8;              // the words requests go to
    localparam N_CLOCKS   = 3000;

    logic                  rst_n;
    logic                  req_valid;
    wire                   req_ready;
    logic                  req_we;
    logic [ADDR_WIDTH-1:0] req_addr;
    logic [DATA_WIDTH-1:0] req_wdata;
    logic [DATA_SIZE-1:0]  req_wstrb;
    wire                   rsp_valid;
    wire  [DATA_WIDTH-1:0] rsp_data;

    logic [7:0]            m [1 << ADDR_WIDTH];  // model of the bytes
    logic [DATA_WIDTH-1:0] w_data [$];           // waiting reads: their words ...
    integer                w_take [$];           // ... and the clock they were taken
    integer                now;
    logic                  req_taken;            // taken at the edge before
    integer                last_write_word;      // word of the last write taken, -1: none
    integer                seed;
    integer                fd;
    string                 hex;

    // Cases seen.
    integer n_b2b;          // a read taken in the clock a full queue answers
    integer n_full;         // a request stopped by a full queue
    integer n_withheld;     // ready withheld with a slot free
    integer n_fast;
    integer n_slow;
    integer n_raw;          // a read of the word the last write wrote
    integer n_partial;      // a write of some bytes only
    integer n_multi;        // two or more reads waiting
    logic [7:0] missing;

    SimLatencyRAM #(.DATA_SIZE(DATA_SIZE), .ADDR_WIDTH(ADDR_WIDTH),
                    .READY_PERCENT(READY_PERCENT), .FAST_PERCENT(FAST_PERCENT),
                    .FAST_MIN(FAST_MIN), .FAST_MAX(FAST_MAX), .SLOW_MIN(SLOW_MIN),
                    .SLOW_MAX(SLOW_MAX), .MAX_PENDING(MAX_PENDING), .SEED(SEED))
        u_sim_latency_ram(.clk, .rst_n, .req_valid, .req_ready, .req_we, .req_addr, .req_wdata,
                          .req_wstrb, .rsp_valid, .rsp_data);

    function automatic logic [DATA_WIDTH-1:0] model_word(input integer word);
        logic [DATA_WIDTH-1:0] d;
        for (int i = 0; i < DATA_SIZE; i++)
            d[8*i +: 8] = m[word * DATA_SIZE + i];
        return d;
    endfunction

    // After the inputs of this clock settled: the outputs are those the rules allow.
    task automatic check;
        integer lat;
        if (rsp_valid) begin
            if (w_data.size() == 0)
                $fatal(1, "SimLatencyRAM %0d: an answer without a waiting read", SEED);
            lat = now - w_take[0];
            if (rsp_data !== w_data[0])
                $fatal(1, "SimLatencyRAM %0d: answer %h, expected %h", SEED, rsp_data, w_data[0]);
            if (lat < 1 || (EXACT && lat != 1))
                $fatal(1, "SimLatencyRAM %0d: latency %0d", SEED, lat);
            if (MAX_PENDING == 1 && !(lat >= FAST_MIN && lat <= FAST_MAX) &&
                !(lat >= SLOW_MIN && lat <= SLOW_MAX))
                $fatal(1, "SimLatencyRAM %0d: latency %0d out of both ranges", SEED, lat);
            if (lat <= FAST_MAX) n_fast = n_fast + 1;
            if (lat >= SLOW_MIN) n_slow = n_slow + 1;
        end
        if (w_data.size() == MAX_PENDING && !rsp_valid && req_ready !== 1'b0)
            $fatal(1, "SimLatencyRAM %0d: ready with %0d reads waiting", SEED, MAX_PENDING);
        if (EXACT && req_ready !== 1'b1)
            $fatal(1, "SimLatencyRAM %0d: not ready at latency 1, READY_PERCENT 100", SEED);
    endtask

    // Model of one rising edge with the inputs of this clock.
    task automatic model_edge;
        logic accept;
        integer word;
        accept = req_valid && req_ready;
        word   = int'(req_addr[ADDR_WIDTH-1:AS]);
        if (req_valid && !req_ready) begin
            if (w_data.size() == MAX_PENDING && !rsp_valid) n_full = n_full + 1;
            else                                          n_withheld = n_withheld + 1;
        end
        if (w_data.size() >= 2)
            n_multi = n_multi + 1;
        if (rsp_valid) begin
            void'(w_data.pop_front());
            void'(w_take.pop_front());
        end
        if (accept && req_we) begin
            for (int i = 0; i < DATA_SIZE; i++)
                if (req_wstrb[i])
                    m[word * DATA_SIZE + i] = req_wdata[8*i +: 8];
            if (req_wstrb != '1)
                n_partial = n_partial + 1;
            last_write_word = word;
        end else if (accept) begin
            if (rsp_valid && w_data.size() == MAX_PENDING - 1)
                n_b2b = n_b2b + 1;
            if (word == last_write_word)
                n_raw = n_raw + 1;
            w_data.push_back(model_word(word));
            w_take.push_back(now);
        end
        req_taken = accept;
        now = now + 1;
    endtask

    // A new request to one of WORDS words.
    task automatic new_request;
        req_we   = 1'($random(seed) & 1);
        req_addr = ADDR_WIDTH'((({$random(seed)} % WORDS) << AS) | ({$random(seed)} % DATA_SIZE));
        for (int i = 0; i < DATA_SIZE; i++)
            req_wdata[8*i +: 8] = 8'($random(seed));
        req_wstrb = (($random(seed) & 3) == 0) ? '1 : DATA_SIZE'($random(seed));
        if (req_wstrb == '0)
            req_wstrb = '1;
        req_valid = 1'b1;
    endtask

    initial begin
        done            = 1'b0;
        seed            = SEED * 7 + 3;
        now             = 0;
        req_taken       = 1'b0;
        last_write_word = -1;
        n_b2b = 0; n_full = 0; n_withheld = 0; n_fast = 0; n_slow = 0; n_raw = 0;
        n_partial = 0; n_multi = 0;
        rst_n     = 1'b0;
        req_valid = 1'b0;
        req_we    = 1'b0;
        req_addr  = '0;
        req_wdata = '0;
        req_wstrb = '0;
        // Memory content from a file, the model the same.
        hex = $sformatf("tb_sim_latency_ram_%0d.hex", SEED);
        fd  = $fopen(hex, "w");
        $fwrite(fd, "@0\n");
        for (int a = 0; a < (1 << ADDR_WIDTH); a++) begin
            m[a] = 8'(a * 37 + SEED);
            $fwrite(fd, "%h\n", m[a]);
        end
        $fclose(fd);
        if (u_sim_latency_ram.load(hex, u_sim_latency_ram.VLOG_HEX_FORMAT) != 1)
            $fatal(1, "SimLatencyRAM %0d: load() failed", SEED);
        for (int a = 0; a < (1 << ADDR_WIDTH); a = a + 17)
            if (u_sim_latency_ram.peek(ADDR_WIDTH'(a)) !== m[a])
                $fatal(1, "SimLatencyRAM %0d: peek(%0d) = %h, expected %h", SEED, a,
                       u_sim_latency_ram.peek(ADDR_WIDTH'(a)), m[a]);
        @(negedge clk);
        @(negedge clk);
        if (rsp_valid !== 1'b0)
            $fatal(1, "SimLatencyRAM %0d: rsp_valid %b during reset", SEED, rsp_valid);
        rst_n = 1'b1;
        for (int k = 0; k < N_CLOCKS; k++) begin
            // The requester holds a request until it is taken, then may send the next.
            if (req_taken)
                req_valid = 1'b0;
            if (!req_valid && {$random(seed)} % 10 < 8)
                new_request();
            #1;
            check();
            model_edge();
            @(negedge clk);
        end
        req_valid = 1'b0;
        // Bit 7 b2b, ... bit 0 multi: a 1 is a case that did not happen.
        missing = REQUIRED & {n_b2b == 0, n_full == 0, n_withheld == 0, n_fast == 0,
                              n_slow == 0, n_raw == 0, n_partial == 0, n_multi == 0};
        if (missing != '0)
            $fatal(1, "SimLatencyRAM %0d: cases that did not happen (b2b first): %b", SEED, missing);
        done = 1'b1;
    end
endmodule

module TbSimLatencyRAM;
    wire       clk;
    wire [2:0] done;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    // Latency 1, always ready: b2b, fast, raw, partial.
    TbSimLatencyRAMCheck #(.SEED(1), .EXACT(1'b1), .REQUIRED(8'b1001_0110)) u_check_1(
        .clk, .done(done[0]));
    // Two-level, one read waiting: everything but two waiting.
    TbSimLatencyRAMCheck #(.READY_PERCENT(70), .FAST_PERCENT(70), .FAST_MIN(1), .FAST_MAX(2),
                           .SLOW_MIN(6), .SLOW_MAX(9), .SEED(2), .REQUIRED(8'b1111_1110))
        u_check_2(.clk, .done(done[1]));
    // Two-level, four reads waiting, words of 8 bytes: everything.
    TbSimLatencyRAMCheck #(.DATA_SIZE(8), .READY_PERCENT(80), .FAST_PERCENT(50), .FAST_MIN(1),
                           .FAST_MAX(3), .SLOW_MIN(8), .SLOW_MAX(12), .MAX_PENDING(4), .SEED(3),
                           .REQUIRED(8'b1111_1111)) u_check_3(.clk, .done(done[2]));

    initial begin
        wait (done == '1);
        $display("PASS");
        $finish;
    end
endmodule
