/* Buffer.
 *
 * Built bit by bit from cell BUF.
 */
module Buf #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        BUF u_buf(.I(in[i]), .Z(out[i]));
    end
    endgenerate

endmodule
