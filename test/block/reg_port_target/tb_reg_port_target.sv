/* Test of RegPortTarget, behave or struct version.
 *
 * The testbench is both sides. The requester offers random reads and writes (random
 * strobes, sometimes nothing) and keeps an offer that is not taken, the same (rule 2); hold
 * is random, from a flop. The device is 16 registers written byte by byte by acc_wr and read
 * by rd_data, and register 15 is a counter that every read of it increments (a side effect:
 * it must happen once per read). A reference model of the same registers, updated where the
 * requester sees a request taken, gives every answer's data: rsp_valid must come exactly one
 * clock after a read is taken, with that data, and at no other time; acc_rd and acc_wr only
 * in the clock a request is taken. 3000 cycles on Verilator, 400 on Icarus, DATA_WIDTH 32 and
 * 64. Every case must happen (checks named cover): reads in two clocks in a row, a read right
 * after a write of the same register, a request held by hold, a write of some bytes only, a
 * read of the counter. Checks named model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbRegPortTargetCheck #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
`ifdef VERILATOR
    localparam N_CYCLES = 3000;
`else
    localparam N_CYCLES = 400;
`endif
    localparam STRB_WIDTH = DATA_WIDTH / 8;
    localparam LSB        = $clog2(STRB_WIDTH);     // the word index starts at this bit
    localparam COUNTER    = 15;                     // the register a read increments

    typedef logic [DATA_WIDTH-1:0] word_t;

    logic                  req_valid;
    wire                   req_ready;
    logic                  req_we;
    logic [ADDR_WIDTH-1:0] req_addr;
    word_t                 req_wdata;
    logic [STRB_WIDTH-1:0] req_wstrb;
    wire                   rsp_valid;
    wire  [DATA_WIDTH-1:0] rsp_rdata;
    logic                  hold;
    wire                   acc_rd;
    wire                   acc_wr;
    // The device has 16 registers: it uses 4 bits of the word address.
    /* verilator lint_off UNUSEDSIGNAL */
    wire  [ADDR_WIDTH-1:0] acc_addr;
    /* verilator lint_on UNUSEDSIGNAL */
    wire  [DATA_WIDTH-1:0] acc_wdata;
    wire  [STRB_WIDTH-1:0] acc_wstrb;
    wire  [DATA_WIDTH-1:0] rd_data;
    integer                seed;

    RegPortTarget #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_reg_port_target(
        .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_addr, .req_wdata, .req_wstrb,
        .rsp_valid, .rsp_rdata, .hold, .acc_rd, .acc_wr, .acc_addr, .acc_wdata, .acc_wstrb,
        .rd_data);

    // old with the bytes of new where strb is 1.
    function automatic word_t merge(input word_t old, input word_t new_w,
                                    input logic [STRB_WIDTH-1:0] strb);
        word_t w;
        w = old;
        for (int b = 0; b < STRB_WIDTH; b++)
            if (strb[b])
                w[8*b +: 8] = new_w[8*b +: 8];
        return w;
    endfunction

    // The device: 16 registers, register COUNTER counts its reads.
    word_t  dev_regs [16];
    word_t  dev_count;
    wire [3:0] dev_word = acc_addr[LSB +: 4];
    assign rd_data = (dev_word == 4'(COUNTER)) ? dev_count : dev_regs[dev_word];

    always @(posedge clk)
        if (!rst_n) begin
            foreach (dev_regs[i])
                dev_regs[i] <= '0;
            dev_count <= '0;
        end else begin
            if (acc_wr)
                dev_regs[dev_word] <= merge(dev_regs[dev_word], acc_wdata, acc_wstrb);
            if (acc_rd && dev_word == 4'(COUNTER))
                dev_count <= dev_count + 1'b1;
        end

    // The reference model, from the requester's side.
    word_t  ref_regs [16];
    word_t  ref_count;
    logic   exp_valid;      // an answer is due after this clock
    word_t  exp_data;
    logic   taken;          // a request is taken in this clock
    logic   last_rd;        // the clock before took a read
    int     last_wr_word;   // the word the clock before wrote, -1 if none
    logic   seen_rd_rd, seen_rd_after_wr, seen_hold, seen_part, seen_counter;

    function automatic word_t random_word();
        word_t w;
        for (int i = 0; i < DATA_WIDTH; i += 32)
            w[i +: 32] = $random(seed);
        return w;
    endfunction

    // A new offer: nothing, a read or a write of a random register.
    task automatic new_request();
        req_valid = ($random(seed) % 4) != 0;
        req_we    = ($random(seed) % 2) != 0;
        req_addr  = ADDR_WIDTH'($random(seed));
        req_wdata = random_word();
        req_wstrb = ($random(seed) % 3 == 0) ? STRB_WIDTH'($random(seed)) : '1;
    endtask

    initial begin
        int w;
        done = 1'b0;
        {seen_rd_rd, seen_rd_after_wr, seen_hold, seen_part, seen_counter} = '0;
        seed = DATA_WIDTH;
        foreach (ref_regs[i])
            ref_regs[i] = '0;
        ref_count    = '0;
        exp_valid    = 1'b0;
        last_rd      = 1'b0;
        last_wr_word = -1;
        hold         = 1'b0;
        new_request();
        @(posedge rst_n);
        @(posedge clk);
        #1;
        repeat (N_CYCLES) begin
            @(negedge clk);
            // The middle of the clock: the outputs of this clock.
            taken = req_valid && !hold;
            w     = int'(req_addr[LSB +: 4]);
            if (req_ready !== !hold || acc_rd !== (taken && !req_we) ||
                acc_wr !== (taken && req_we))
                `DC_TEST_FAIL(model, $sformatf({
                    "RegPortTarget DATA_WIDTH=%0d: ready %b acc_rd %b acc_wr %b, ",
                    "valid %b we %b hold %b"},
                    DATA_WIDTH, req_ready, acc_rd, acc_wr, req_valid, req_we, hold))
            if (req_valid && hold)
                seen_hold = 1'b1;
            exp_valid = taken && !req_we;
            if (taken && !req_we) begin
                exp_data = (w == COUNTER) ? ref_count : ref_regs[w];
                if (w == COUNTER) begin
                    ref_count    = ref_count + 1'b1;
                    seen_counter = 1'b1;
                end
                if (last_rd)
                    seen_rd_rd = 1'b1;
                if (last_wr_word == w && w != COUNTER)
                    seen_rd_after_wr = 1'b1;
            end
            if (taken && req_we) begin
                ref_regs[w] = merge(ref_regs[w], req_wdata, req_wstrb);
                if (req_wstrb != '1 && req_wstrb != '0)
                    seen_part = 1'b1;
            end
            last_rd      = taken && !req_we;
            last_wr_word = (taken && req_we) ? w : -1;
            @(posedge clk);
            #1;
            // After the edge: the answer of a read taken in the clock before.
            if (rsp_valid !== exp_valid || (exp_valid && rsp_rdata !== exp_data))
                `DC_TEST_FAIL(model, $sformatf(
                    "RegPortTarget DATA_WIDTH=%0d: rsp %b %h, expected %b %h",
                    DATA_WIDTH, rsp_valid, rsp_rdata, exp_valid, exp_data))
            // The next offer: a new one after a request was taken or nothing offered, else the
            // same (rule 2); the next hold, from this flop-like change after the edge.
            if (taken || !req_valid) begin
                new_request();
                // Now and then a read of the register written just now.
                if (last_wr_word >= 0 && $random(seed) % 3 == 0) begin
                    req_valid = 1'b1;
                    req_we    = 1'b0;
                    req_addr  = ADDR_WIDTH'(last_wr_word << LSB);
                end
            end
            hold = ($random(seed) % 4) == 0;
        end
        if (!seen_rd_rd || !seen_rd_after_wr || !seen_hold || !seen_part || !seen_counter)
            `DC_TEST_FAIL(cover, $sformatf({
                "RegPortTarget DATA_WIDTH=%0d: rd rd %b rd after wr %b hold %b part %b ",
                "counter %b"},
                DATA_WIDTH, seen_rd_rd, seen_rd_after_wr, seen_hold, seen_part, seen_counter))
        done = 1'b1;
    end
endmodule

module TbRegPortTarget;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_32;
    wire  done_64;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbRegPortTargetCheck #(.ADDR_WIDTH(8),  .DATA_WIDTH(32)) u_check_32(
        .clk, .rst_n, .done(done_32));
    TbRegPortTargetCheck #(.ADDR_WIDTH(12), .DATA_WIDTH(64)) u_check_64(
        .clk, .rst_n, .done(done_64));

    initial begin
        wait (done_32 && done_64);
        $display("PASS");
        $finish;
    end
endmodule
