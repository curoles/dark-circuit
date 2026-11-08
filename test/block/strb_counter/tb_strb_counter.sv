/* Test of StrbCounter, behave or struct version.
 *
 * Model: the counter as a number of whole bytes, a byte taken whole when it is written, a
 * count an addition (a different view from the RTL's bit loop or byte muxes). WIDTH 1, 3, 8,
 * 12, 33 and 64, each with a reset value of its own (not 0): after reset q must be RST_VAL;
 * then random we, strobes, data and inc every clock, q compared with the model after every
 * edge: 1000 cycles on Verilator, 200 on Icarus. One write in four sets the low bytes to all
 * ones, so that counts carry across bytes and wrap. Every case must happen (checks named
 * cover): a write of all bytes, of some bytes, with no strobe (no count either), a write and
 * inc in one clock (the write wins), a count that carries out of byte 0 (WIDTH > 8) or wraps
 * to 0, a clock that keeps the value. Checks named model and cover. Stops at the first
 * failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbStrbCounterCheck #(
    parameter             WIDTH   = 64,
    parameter [WIDTH-1:0] RST_VAL = '0
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
`ifdef VERILATOR
    localparam N_CYCLES = 1000;
`else
    localparam N_CYCLES = 200;
`endif
    localparam NBYTES = (WIDTH + 7) / 8;

    logic              we;
    logic [NBYTES-1:0] wstrb;
    logic [WIDTH-1:0]  wdata;
    logic              inc;
    wire  [WIDTH-1:0]  q;
    logic [WIDTH-1:0]  model;
    integer            seed;
    logic seen_all, seen_some, seen_none, seen_both, seen_carry, seen_keep;

    StrbCounter #(.WIDTH(WIDTH), .RST_VAL(RST_VAL)) u_strb_counter(
        .clk, .rst_n, .we, .wstrb, .wdata, .inc, .q);

    initial begin
        // The model and wdata in whole bytes: the bits above WIDTH are not used.
        /* verilator lint_off UNUSEDSIGNAL */
        logic [8*NBYTES-1:0] wide;
        logic [8*NBYTES-1:0] wide_data;
        /* verilator lint_on UNUSEDSIGNAL */
        done = 1'b0;
        {seen_all, seen_some, seen_none, seen_both, seen_carry, seen_keep} = '0;
        seed  = WIDTH;
        we    = 1'b0;
        wstrb = '0;
        wdata = '0;
        inc   = 1'b0;
        model = RST_VAL;
        @(posedge rst_n);
        #1;
        if (q !== RST_VAL)
            `DC_TEST_FAIL(model, $sformatf("StrbCounter WIDTH=%0d: q %h after reset, expected %h",
                                           WIDTH, q, RST_VAL))
        repeat (N_CYCLES) begin
            we    = ($random(seed) % 4) == 0;
            inc   = ($random(seed) % 4) != 0;
            wstrb = NBYTES'($random(seed));
            if ($random(seed) % 4 == 0)
                wstrb = '1;
            wdata = WIDTH'({$random(seed), $random(seed)});
            if ($random(seed) % 4 == 0)
                wdata = WIDTH'({$random(seed), {32{1'b1}}});    // low bytes all ones
            if (we) begin
                wide      = (8*NBYTES)'(model);
                wide_data = (8*NBYTES)'(wdata);
                for (int b = 0; b < NBYTES; b++)
                    if (wstrb[b])
                        wide[8*b +: 8] = wide_data[8*b +: 8];
                model = WIDTH'(wide);
            end else if (inc) begin
                // The low byte all ones (below 8 bits: all ones, a wrap).
                if ((model & WIDTH'(8'hff)) == WIDTH'(8'hff))
                    seen_carry = 1'b1;
                model = model + 1'b1;
            end else
                seen_keep = 1'b1;
            if (we && wstrb == '1)
                seen_all = 1'b1;
            if (we && wstrb != '1 && wstrb != '0)
                seen_some = 1'b1;
            if (we && wstrb == '0)
                seen_none = 1'b1;
            if (we && inc)
                seen_both = 1'b1;
            @(posedge clk);
            #1;
            if (q !== model)
                `DC_TEST_FAIL(model, $sformatf("StrbCounter WIDTH=%0d: q %h, expected %h",
                                               WIDTH, q, model))
        end
        if (!seen_all || (NBYTES > 1 && !seen_some) || !seen_none || !seen_both ||
            !seen_carry || !seen_keep)
            `DC_TEST_FAIL(cover, $sformatf(
                "StrbCounter WIDTH=%0d: all %b some %b none %b both %b carry %b keep %b",
                WIDTH, seen_all, seen_some, seen_none, seen_both, seen_carry, seen_keep))
        done = 1'b1;
    end
endmodule

module TbStrbCounter;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_1, done_3, done_8, done_12, done_33, done_64;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbStrbCounterCheck #(.WIDTH(1),  .RST_VAL(1'b1))  u_check_1(.clk, .rst_n, .done(done_1));
    TbStrbCounterCheck #(.WIDTH(3),  .RST_VAL(3'h5))  u_check_3(.clk, .rst_n, .done(done_3));
    TbStrbCounterCheck #(.WIDTH(8),  .RST_VAL(8'ha5)) u_check_8(.clk, .rst_n, .done(done_8));
    TbStrbCounterCheck #(.WIDTH(12), .RST_VAL(12'h9c3)) u_check_12(
        .clk, .rst_n, .done(done_12));
    TbStrbCounterCheck #(.WIDTH(33), .RST_VAL(33'h1_8000_0001)) u_check_33(
        .clk, .rst_n, .done(done_33));
    TbStrbCounterCheck #(.WIDTH(64), .RST_VAL(64'hffff_fff0_0000_0003)) u_check_64(
        .clk, .rst_n, .done(done_64));

    initial begin
        wait (done_1 && done_3 && done_8 && done_12 && done_33 && done_64);
        $display("PASS");
        $finish;
    end
endmodule
