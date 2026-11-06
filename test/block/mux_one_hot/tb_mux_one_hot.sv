/* Test of MuxOneHot, behave or struct version.
 *
 * Model: out bit by bit, a bit 1 when some selected input has it 1 (the RTL goes input by
 * input or uses gates). Sizes: N 1, 2, 3, 5 and 17 with widths of 1, 8, 5, 32 and 3. Random
 * inputs every step with a select of no input, of one input (half the steps) or of random
 * inputs (their OR); 1000 steps on Verilator, 200 on Icarus. Every input must have been
 * selected alone, and no select and several selects must have happened (checks named
 * cover). Checks named model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbMuxOneHotCheck #(
    parameter N     = 4,
    parameter WIDTH = 1
)(
    output logic done
);
`ifdef VERILATOR
    localparam N_STEPS = 1000;
`else
    localparam N_STEPS = 200;
`endif

    logic [N-1:0][WIDTH-1:0] in;
    logic [N-1:0]            sel;
    wire  [WIDTH-1:0]        out;
    logic [WIDTH-1:0]        exp_out;
    logic [N-1:0]            seen_alone;    // input k has been selected alone
    logic                    seen_none, seen_many;
    integer                  seed;

    MuxOneHot #(.N(N), .WIDTH(WIDTH)) u_mux_one_hot(.in, .sel, .out);

    initial begin
        int               kind;
        logic [WIDTH-1:0] row;
        done = 1'b0;
        seen_alone = '0;
        {seen_none, seen_many} = '0;
        seed = N * 64 + WIDTH;
        repeat (N_STEPS) begin
            for (int k = 0; k < N; k++)
                in[k] = WIDTH'($random(seed));
            kind = {$random(seed)} % 4;
            if (kind == 0)
                sel = '0;
            else if (kind == 3)
                sel = N'($random(seed));
            else
                sel = N'(1) << ({$random(seed)} % N);
            for (int b = 0; b < WIDTH; b++) begin
                exp_out[b] = 1'b0;
                for (int k = 0; k < N; k++) begin
                    row = in[k];    // in[k][b], both variable: Icarus (AGENTS.md)
                    if (sel[k] && row[b])
                        exp_out[b] = 1'b1;
                end
            end
            if (sel == '0)
                seen_none = 1'b1;
            else if ($onehot(sel))
                seen_alone = seen_alone | sel;
            else
                seen_many = 1'b1;
            #1;
            if (out !== exp_out)
                `DC_TEST_FAIL(model, $sformatf({
                    "MuxOneHot N=%0d WIDTH=%0d: sel %b, out %h, expected %h"},
                    N, WIDTH, sel, out, exp_out))
        end
        if (seen_alone !== '1 || !seen_none || (N > 1 && !seen_many))
            `DC_TEST_FAIL(cover, $sformatf("MuxOneHot N=%0d WIDTH=%0d: alone %b none %b many %b",
                                           N, WIDTH, seen_alone, seen_none, seen_many))
        done = 1'b1;
    end
endmodule

module TbMuxOneHot;
    `DC_TEST_MUTANT_HOOK(top)

    wire [4:0] done;

    TbMuxOneHotCheck #(.N(1),  .WIDTH(1))  u_check_1 (.done(done[0]));
    TbMuxOneHotCheck #(.N(2),  .WIDTH(8))  u_check_2 (.done(done[1]));
    TbMuxOneHotCheck #(.N(3),  .WIDTH(5))  u_check_3 (.done(done[2]));
    TbMuxOneHotCheck #(.N(5),  .WIDTH(32)) u_check_5 (.done(done[3]));
    TbMuxOneHotCheck #(.N(17), .WIDTH(3))  u_check_17(.done(done[4]));

    initial begin
        wait (done == '1);
        $display("PASS");
        $finish;
    end
endmodule
