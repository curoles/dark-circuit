/* Stochastic bitstream generator: binary_in -> 1-bit stream with density of ones
 * binary_in / (2^WIDTH - 1), behavioral.
 *
 * Stochastic computing encodes a number as the probability of 1 in a bitstream;
 * then, for example, AND of two independent streams is the product of their values.
 * Every clock stream_out = binary_in >= r, r is the Lfsr value. Lfsr visits each of
 * 1..2^WIDTH-1 once per period, so over any 2^WIDTH - 1 consecutive clocks stream_out
 * is 1 exactly binary_in times: 0 gives no ones, all ones gives only ones.
 * stream_out is registered, 0 during reset.
 * Streams that are combined must be uncorrelated: generators with the same WIDTH and
 * SEED give the same stream, and AND of them is the minimum, not the product.
 * Supported WIDTH: as Lfsr, 4, 8, 12, 16, 32.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module StochasticBitstreamGen #(
    parameter             WIDTH = 8,
    parameter [WIDTH-1:0] SEED  = {WIDTH{1'b1}}  // Lfsr value after reset, not 0
)(
    input  wire             clk,
    input  wire             rst_n,       // synchronous reset, active low
    input  wire [WIDTH-1:0] binary_in,
    output reg              stream_out
);
    wire [WIDTH-1:0] r;   // Lfsr: uniform over 1..2^WIDTH-1

    Lfsr #(.WIDTH(WIDTH), .SEED(SEED)) u_lfsr(.clk(clk), .rst_n(rst_n), .q(r));

    always_ff @(posedge clk)
        if (!rst_n)
            stream_out <= 1'b0;
        else
            stream_out <= binary_in >= r;

endmodule
