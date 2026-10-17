/* Linear feedback shift register (LFSR), Galois form, made of gates.
 *
 * Author: Igor Lesik
 *
 * q steps through all 2^WIDTH - 1 nonzero values before it repeats (maximal period):
 * on every rising edge q shifts right and, when the bit shifted out is 1, the tap mask
 * of LfsrPkg is XORed in. Supported WIDTH: 4, 8, 12, 16, 32; any other width stops
 * the simulation. rst_n=0 on rising edge sets q to all ones: the zero state would
 * lock the LFSR.
 *
 * Next value, bit by bit: a bit with a tap is Xor2 of the shifted bit and q[0],
 * other bits are the shifted bit. DffSyncRst resets q to all ones (RST_VAL).
 */
module Lfsr import LfsrPkg::*; #(
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst_n,  // synchronous reset, active low
    output wire [WIDTH-1:0] q
);
    localparam [31:0]      TAPS     = lfsr_taps(WIDTH);
    localparam [WIDTH-1:0] TAP_MASK = TAPS[WIDTH-1:0];

    initial
        if (TAPS == 0)
            $fatal(1, "Lfsr: WIDTH=%0d is not supported, see LfsrPkg", WIDTH);

    wire [WIDTH-1:0] shifted;  // q shifted right by 1
    wire [WIDTH-1:0] next;

    assign shifted = {1'b0, q[WIDTH-1:1]};

    for (genvar i = 0; i < WIDTH; i++) begin: g_bit
        if (TAP_MASK[i]) begin: g_tap
            Xor2 #(1) u_xor2(.in1(shifted[i]), .in2(q[0]), .out(next[i]));
        end else begin: g_shift
            assign next[i] = shifted[i];
        end
    end

    DffSyncRst #(.WIDTH(WIDTH), .RST_VAL({WIDTH{1'b1}})) u_dff_sync_rst(
        .clk(clk), .rst_n(rst_n), .in(next), .out(q));

endmodule
