/* Test of StrbReg, behave or struct version.
 *
 * Model: the register as a vector of bytes, a byte taken whole when it is written (a
 * different view from the RTL's bit or byte loops). WIDTH 1, 3, 8, 12, 32 and 33 (one
 * partial byte, whole bytes, a partial last byte), each with a reset value of its own (not
 * 0): after reset q must be RST_VAL; then random we, strobes and data every clock, q compared
 * with the model after every edge: 1000 cycles on Verilator, 200 on Icarus. Every case must
 * happen (checks named cover): a write of all bytes, of some bytes, with no strobe, a clock
 * without we but with strobes. Checks named model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbStrbRegCheck #(
    parameter             WIDTH   = 32,
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
    wire  [WIDTH-1:0]  q;
    logic [8*NBYTES-1:0] model;     // whole bytes; the bits above WIDTH stay 0
    integer            seed;
    logic seen_all, seen_some, seen_none, seen_no_we;

    StrbReg #(.WIDTH(WIDTH), .RST_VAL(RST_VAL)) u_strb_reg(
        .clk, .rst_n, .we, .wstrb, .wdata, .q);

    initial begin
        logic [8*NBYTES-1:0] wide;  // wdata in whole bytes
        done = 1'b0;
        {seen_all, seen_some, seen_none, seen_no_we} = '0;
        seed  = WIDTH;
        we    = 1'b0;
        wstrb = '0;
        wdata = '0;
        model = (8*NBYTES)'(RST_VAL);
        @(posedge rst_n);
        #1;
        if (q !== RST_VAL)
            `DC_TEST_FAIL(model, $sformatf("StrbReg WIDTH=%0d: q %h after reset, expected %h",
                                           WIDTH, q, RST_VAL))
        repeat (N_CYCLES) begin
            we    = ($random(seed) % 3) != 0;
            wstrb = NBYTES'($random(seed));
            if ($random(seed) % 4 == 0)
                wstrb = '1;
            wdata = WIDTH'({$random(seed), $random(seed)});
            wide  = (8*NBYTES)'(wdata);
            if (we)
                for (int b = 0; b < NBYTES; b++)
                    if (wstrb[b])
                        model[8*b +: 8] = wide[8*b +: 8];
            if (we && wstrb == '1)
                seen_all = 1'b1;
            if (we && wstrb != '1 && wstrb != '0)
                seen_some = 1'b1;
            if (we && wstrb == '0)
                seen_none = 1'b1;
            if (!we && wstrb != '0)
                seen_no_we = 1'b1;
            @(posedge clk);
            #1;
            if ((8*NBYTES)'(q) !== model)
                `DC_TEST_FAIL(model, $sformatf("StrbReg WIDTH=%0d: q %h, expected %h",
                                               WIDTH, q, model))
        end
        if (!seen_all || (NBYTES > 1 && !seen_some) || !seen_none || !seen_no_we)
            `DC_TEST_FAIL(cover, $sformatf("StrbReg WIDTH=%0d: all %b some %b none %b no we %b",
                                           WIDTH, seen_all, seen_some, seen_none, seen_no_we))
        done = 1'b1;
    end
endmodule

module TbStrbReg;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_1, done_3, done_8, done_12, done_32, done_33;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbStrbRegCheck #(.WIDTH(1),  .RST_VAL(1'b1))  u_check_1(.clk, .rst_n, .done(done_1));
    TbStrbRegCheck #(.WIDTH(3),  .RST_VAL(3'h5))  u_check_3(.clk, .rst_n, .done(done_3));
    TbStrbRegCheck #(.WIDTH(8),  .RST_VAL(8'ha5)) u_check_8(.clk, .rst_n, .done(done_8));
    TbStrbRegCheck #(.WIDTH(12), .RST_VAL(12'h9c3)) u_check_12(.clk, .rst_n, .done(done_12));
    TbStrbRegCheck #(.WIDTH(32), .RST_VAL(32'h1234_5678)) u_check_32(
        .clk, .rst_n, .done(done_32));
    TbStrbRegCheck #(.WIDTH(33), .RST_VAL(33'h1_8000_0001)) u_check_33(
        .clk, .rst_n, .done(done_33));

    initial begin
        wait (done_1 && done_3 && done_8 && done_12 && done_32 && done_33);
        $display("PASS");
        $finish;
    end
endmodule
