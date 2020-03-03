

/**
 *
 * i[j] - take j-th bit of number i
 * For example, for 3-8 decoder:
 *     If in is 5(101), 5[0]=1, 5[1]=0, 5[2]=1
 *     for i [0..7]
 *         i=5=b101, 5[0]=1, 5[1]=0, 5[2]=1
 *         out[5]=5[0] & !5[1] & !5[2] = 1 & !0 & 1 = 1
 *
 *         i=6=b110, 6[0]=0, 6[1]=1, 6[2]=1
 *         out[6]=!5[0] & 5[1] & 5[2] = !1 & 0 & 1 = 0 & 0 & 1 = 0
 *
 */
module Decoder #(
    parameter SIZE = 3,
    parameter WIDTH = 1 << SIZE
)(
    input  wire [SIZE-1:0]  in,
    input  wire             en,
    output wire [WIDTH-1:0] out
);

wire [SIZE-1:0] nin;
assign nin = ~in;

genvar i, j;
generate
for (i = 0; i < WIDTH; i = i + 1) begin
    wire [ADDR_SIZE-1:0] sel;
    for (j = 0; j < SIZE; j = j + 1) begin
        assign sel[j] = i[j] ? in[j] : nin[j];
    end
    assign out[i] = en & ( &sel );
end
endgenerate

endmodule
