/* Stochastic bitstream generator: binary_in -> 1-bit stream with density of ones
 * binary_in / (2^WIDTH - 1), made of blocks, parts and gates.
 *
 * Author: Igor Lesik
 *
 * Same behavior as the behave version, see there. binary_in >= r is the carry out of
 * binary_in - r = binary_in + ~r + 1: carry 1 means no borrow. DffSyncRst registers it.
 */
module StochasticBitstreamGen #(
    parameter             WIDTH = 8,
    parameter [WIDTH-1:0] SEED  = {WIDTH{1'b1}}  // Lfsr value after reset, not 0
)(
    input  wire             clk,
    input  wire             rst_n,       // synchronous reset, active low
    input  wire [WIDTH-1:0] binary_in,
    output wire             stream_out
);
    wire [WIDTH-1:0] r;       // Lfsr: uniform over 1..2^WIDTH-1
    wire [WIDTH-1:0] r_inv;
    wire             ge;      // binary_in >= r
    // Only the carry out of the subtraction is used.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [WIDTH-1:0] diff;
    /* verilator lint_on UNUSEDSIGNAL */

    Lfsr #(.WIDTH(WIDTH), .SEED(SEED)) u_lfsr(.clk(clk), .rst_n(rst_n), .q(r));

    Inv #(WIDTH) u_inv(.in(r), .out(r_inv));
    RippleCarryAdder #(.WIDTH(WIDTH)) u_ripple_carry_adder(
        .in1(binary_in), .in2(r_inv), .ci(1'b1), .co(ge), .sum(diff));

    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst(.clk(clk), .rst_n(rst_n), .in(ge), .out(stream_out));

endmodule
