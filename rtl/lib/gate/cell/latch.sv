/* Latch, transparent while enable is 1.
 *
 * Built bit by bit from cell LHQ.
 */
module Latch #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,
    input  wire             enable,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        LHQ u_lhq(.D(in[i]), .E(enable), .Q(out[i]));
    end
    endgenerate

endmodule
