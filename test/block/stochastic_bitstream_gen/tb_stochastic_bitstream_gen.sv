/* Test of StochasticBitstreamGen, behave or struct version.
 *
 * Density: for WIDTH 4 and 8 and binary_in 0, 1, middle and all ones, stream_out is 1
 * exactly binary_in times in 2^WIDTH - 1 clocks.
 * Product: AND of two WIDTH=8 streams with different SEED is 1 about a*b/255 times
 * in 255 clocks; the tolerance is 4, the largest error measured with a model over
 * a grid of a, b was 3.3.
 * Stops at the first mismatch with $fatal.
 */
module TbStochasticDensity #(
    parameter WIDTH = 4,
    parameter VALUE = 0
)(
    input  wire clk,
    input  wire rst_n,
    output reg  done
);
    localparam N = (1 << WIDTH) - 1;   // Lfsr period

    wire [WIDTH-1:0] binary_in;
    wire             stream_out;
    integer          ones;

    assign binary_in = VALUE;

    StochasticBitstreamGen #(.WIDTH(WIDTH)) u_stochastic_bitstream_gen(
        .clk(clk), .rst_n(rst_n), .binary_in(binary_in), .stream_out(stream_out));

    initial begin
        done = 0;
        ones = 0;
        @(posedge rst_n);
        repeat (3) @(negedge clk);     // stream_out of a clock after reset
        repeat (N) begin
            if (stream_out)
                ones = ones + 1;
            @(negedge clk);
        end
        if (ones != VALUE)
            $fatal(1, "StochasticBitstreamGen %0d: binary_in %0d gave %0d ones in %0d clocks",
                   WIDTH, VALUE, ones, N);
        done = 1;
    end
endmodule

module TbStochasticProduct #(
    parameter A = 128,
    parameter B = 128
)(
    input  wire clk,
    input  wire rst_n,
    output reg  done
);
    wire [7:0] a;
    wire [7:0] b;
    wire       stream_a;
    wire       stream_b;
    integer    ones;
    integer    err;   // 255 * ones - A * B: error of ones times 255

    assign a = A;
    assign b = B;

    StochasticBitstreamGen #(.WIDTH(8), .SEED(8'hFF)) u_stochastic_bitstream_gen_a(
        .clk(clk), .rst_n(rst_n), .binary_in(a), .stream_out(stream_a));
    StochasticBitstreamGen #(.WIDTH(8), .SEED(8'h5A)) u_stochastic_bitstream_gen_b(
        .clk(clk), .rst_n(rst_n), .binary_in(b), .stream_out(stream_b));

    initial begin
        done = 0;
        ones = 0;
        @(posedge rst_n);
        repeat (3) @(negedge clk);
        repeat (255) begin
            if (stream_a && stream_b)
                ones = ones + 1;
            @(negedge clk);
        end
        err = 255 * ones - A * B;
        if (err > 4 * 255 || err < -4 * 255)
            $fatal(1, "StochasticBitstreamGen: AND of %0d and %0d gave %0d ones, expected about %0d",
                   A, B, ones, A * B / 255);
        done = 1;
    end
endmodule

module TbStochasticBitstreamGen;
    wire       clk;
    wire       rst_n;
    wire [9:0] done;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));
    SimRstGen #(.CYCLES(2))      u_sim_rst_gen(.clk(clk), .rst_n(rst_n));

    TbStochasticDensity #(.WIDTH(4), .VALUE(0))   u_tb_density_4_0  (.clk(clk), .rst_n(rst_n), .done(done[0]));
    TbStochasticDensity #(.WIDTH(4), .VALUE(1))   u_tb_density_4_1  (.clk(clk), .rst_n(rst_n), .done(done[1]));
    TbStochasticDensity #(.WIDTH(4), .VALUE(7))   u_tb_density_4_7  (.clk(clk), .rst_n(rst_n), .done(done[2]));
    TbStochasticDensity #(.WIDTH(4), .VALUE(15))  u_tb_density_4_15 (.clk(clk), .rst_n(rst_n), .done(done[3]));
    TbStochasticDensity #(.WIDTH(8), .VALUE(0))   u_tb_density_8_0  (.clk(clk), .rst_n(rst_n), .done(done[4]));
    TbStochasticDensity #(.WIDTH(8), .VALUE(1))   u_tb_density_8_1  (.clk(clk), .rst_n(rst_n), .done(done[5]));
    TbStochasticDensity #(.WIDTH(8), .VALUE(128)) u_tb_density_8_128(.clk(clk), .rst_n(rst_n), .done(done[6]));
    TbStochasticDensity #(.WIDTH(8), .VALUE(255)) u_tb_density_8_255(.clk(clk), .rst_n(rst_n), .done(done[7]));

    TbStochasticProduct #(.A(128), .B(128)) u_tb_product_128_128(.clk(clk), .rst_n(rst_n), .done(done[8]));
    TbStochasticProduct #(.A(200), .B(100)) u_tb_product_200_100(.clk(clk), .rst_n(rst_n), .done(done[9]));

    initial begin
        wait (&done);
        $display("PASS");
        $finish;
    end
endmodule
