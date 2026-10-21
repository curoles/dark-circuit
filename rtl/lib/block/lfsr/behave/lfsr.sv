/* Linear feedback shift register (LFSR), Galois form, behavioral.
 *
 * q steps through all 2^WIDTH - 1 nonzero values before it repeats (maximal period):
 * on every rising edge q shifts right and, when the bit shifted out is 1, the tap mask
 * of LfsrPkg is XORed in. Supported WIDTH: 4, 8, 12, 16, 32; any other width stops
 * the simulation. rst_n=0 on rising edge sets q to SEED, all ones by default; SEED=0
 * stops the simulation: the zero state would lock the LFSR. Lfsrs with different SEED
 * give the same sequence at different phases.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Lfsr import LfsrPkg::*; #(
    parameter             WIDTH = 8,
    parameter [WIDTH-1:0] SEED  = {WIDTH{1'b1}}  // q after reset, not 0
)(
    input  wire             clk,
    input  wire             rst_n,  // synchronous reset, active low
    output reg  [WIDTH-1:0] q
);
    localparam [31:0]      TAPS     = lfsr_taps(WIDTH);
    localparam [WIDTH-1:0] TAP_MASK = TAPS[WIDTH-1:0];

    initial
        if (TAPS == 0)
            $fatal(1, "Lfsr: WIDTH=%0d is not supported, see LfsrPkg", WIDTH);
    initial
        if (SEED == 0)
            $fatal(1, "Lfsr: SEED=0 would lock the LFSR");

    always_ff @(posedge clk)
        if (!rst_n)
            q <= SEED;
        else if (q[0])
            q <= (q >> 1) ^ TAP_MASK;
        else
            q <= q >> 1;

endmodule
