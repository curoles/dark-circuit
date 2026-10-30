/* Test of MuxN, behave or struct version.
 *
 * For every N and WIDTH below, every allowed sel with random inputs, ROUNDS times: out must
 * be the input sel names, found by a loop over the inputs (not by an index). The sizes give
 * every shape of the struct tree: one Mux2 (2), one Mux3 (3), one Mux4 (4), a lone node
 * passed up and a Mux2 on top (5), a Mux2 in a level of Mux4 (6), the Mux8 shape (8), a Mux3
 * above Mux4 (9), two levels of Mux4 (16), three levels (17).
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMuxNCheck #(
    parameter N     = 4,
    parameter WIDTH = 1
)(
    output logic done
);
    localparam SEL_WIDTH = $clog2(N);
    localparam ROUNDS    = 20;

    logic [N-1:0][WIDTH-1:0] in;
    logic [SEL_WIDTH-1:0]    sel;
    wire  [WIDTH-1:0]        out;
    logic [WIDTH-1:0]        exp_out;
    integer                  seed;

    MuxN #(.N(N), .WIDTH(WIDTH)) u_mux_n(.in, .sel, .out);

    initial begin
        done = 1'b0;
        seed = N * 64 + WIDTH;
        for (int r = 0; r < ROUNDS; r++) begin
            for (int k = 0; k < N; k++)
                in[k] = WIDTH'($random(seed));
            for (int s = 0; s < N; s++) begin
                sel = SEL_WIDTH'(s);
                for (int k = 0; k < N; k++)
                    if (k == s)
                        exp_out = in[k];
                #1;
                if (out !== exp_out)
                    $fatal(1, "MuxN N=%0d WIDTH=%0d: sel=%0d got %h, expected %h", N, WIDTH, s, out,
                           exp_out);
            end
        end
        done = 1'b1;
    end
endmodule

module TbMuxN;
    wire [8:0] done;

    TbMuxNCheck #(.N(2),  .WIDTH(1)) u_check_2 (.done(done[0]));
    TbMuxNCheck #(.N(3),  .WIDTH(4)) u_check_3 (.done(done[1]));
    TbMuxNCheck #(.N(4),  .WIDTH(8)) u_check_4 (.done(done[2]));
    TbMuxNCheck #(.N(5),  .WIDTH(3)) u_check_5 (.done(done[3]));
    TbMuxNCheck #(.N(6),  .WIDTH(8)) u_check_6 (.done(done[4]));
    TbMuxNCheck #(.N(8),  .WIDTH(2)) u_check_8 (.done(done[5]));
    TbMuxNCheck #(.N(9),  .WIDTH(5)) u_check_9 (.done(done[6]));
    TbMuxNCheck #(.N(16), .WIDTH(8)) u_check_16(.done(done[7]));
    TbMuxNCheck #(.N(17), .WIDTH(3)) u_check_17(.done(done[8]));

    initial begin
        wait (done == '1);
        $display("PASS");
        $finish;
    end
endmodule
