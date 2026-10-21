/* Decoder SIZE to 2**SIZE, made of gates: out[in] = en, all other bits are 0.
 *
 * How it works.
 *
 * Decoder turns binary number into one-hot: for input in=k only output out[k] is 1.
 * There is one detector per output, out[i] answers "is in exactly equal to i?".
 *
 * "in equals i" means every bit of in matches the same bit of i:
 * - where bit j of i is 1, we need in[j]=1, so we use in[j] as is;
 * - where bit j of i is 0, we need in[j]=0, so we use inverted bit ~in[j],
 *   it is 1 exactly when in[j] is 0.
 * out[i] is AND of those chosen bits and en. AND is 1 only if all bits match,
 * that is in == i.
 *
 * For 3 to 8 decoder, AND inputs of every output come from bits of i:
 *
 *   i   bits of i (2 1 0)   out[i] = AND of
 *   0   0 0 0               en & ~in[2] & ~in[1] & ~in[0]
 *   1   0 0 1               en & ~in[2] & ~in[1] &  in[0]
 *   5   1 0 1               en &  in[2] & ~in[1] &  in[0]
 *   7   1 1 1               en &  in[2] &  in[1] &  in[0]
 *
 * Check in=5=101: out[5] gets in[2]=1, ~in[1]=1, in[0]=1, so it is 1;
 * out[7] gets in[1]=0, so it is 0. For any i != 5 at least one bit differs,
 * so at least one AND input is 0: exactly one-hot.
 *
 * How it maps to the code:
 * - Inv u_inv makes all inverted bits in_n = ~in once, shared by every output.
 * - Loop over i builds one detector per output.
 * - Loop over j checks bit j of constant i and wires in[j] or in_n[j] into sel[j];
 *   it happens at elaboration, in hardware it is just wiring, no multiplexer.
 * - sel[SIZE] = en adds enable as one more AND input.
 * - AndReduce does the AND (balanced tree of AN2 cells with gate/cell).
 *
 * Cost: 2**SIZE outputs, each with SIZE+1 input AND; this is why behavioral
 * version (out = en << in) is much faster to simulate for wide decoders.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Decoder #(
    parameter  SIZE  = 3,
    localparam WIDTH = 1 << SIZE
)(
    input  wire [SIZE-1:0]  in,
    input  wire             en,
    output wire [WIDTH-1:0] out
);
    wire [SIZE-1:0] in_n;

    Inv #(SIZE) u_inv(.in(in), .out(in_n));

    genvar i, j;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_out
        wire [SIZE:0] sel;  // chosen input bits and en
        for (j = 0; j < SIZE; j = j + 1) begin: g_bit
            if (((i >> j) & 1) == 1) begin: g_in
                assign sel[j] = in[j];
            end else begin: g_in_n
                assign sel[j] = in_n[j];
            end
        end
        assign sel[SIZE] = en;
        AndReduce #(SIZE+1) u_and_reduce(.in(sel), .out(out[i]));
    end
    endgenerate

endmodule
