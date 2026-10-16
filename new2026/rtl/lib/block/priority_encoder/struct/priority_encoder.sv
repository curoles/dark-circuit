/* Priority encoder 2**SIZE to SIZE, made of gates:
 * out is index of the highest bit set in in, valid is 1 if any bit of in is set;
 * out and valid are 0 when in is 0.
 *
 * How it works, in 2 steps; it is the mirror of the structural Decoder.
 *
 * 1. Keep only the highest set bit, that gives one-hot vector top.
 *    above[k] is "some bit higher than k is set", it is chain of OR gates
 *    from the top: above[WIDTH-1] = 0, above[k] = in[k+1] | above[k+1].
 *    top[k] = in[k] & ~above[k]: bit k is set and no higher bit is set.
 *
 * 2. Turn one-hot top into binary number: out[j] is OR of every top[k]
 *    where bit j of k is 1. Decoder uses bits of constant i to choose wires
 *    for AND, here bits of constant k choose wires for OR.
 *    For 8 to 3 priority encoder:
 *
 *      out[0] = top[1] | top[3] | top[5] | top[7]
 *      out[1] = top[2] | top[3] | top[6] | top[7]
 *      out[2] = top[4] | top[5] | top[6] | top[7]
 *
 *    Half of all k have bit j set; m-th of them is m with bit 1 inserted at
 *    position j: k = ((m >> j) << (j+1)) | (1 << j) | (m & ((1 << j) - 1)).
 *
 * valid = in[0] | above[0], some bit at or above 0 is set.
 *
 * Chain of above is ripple, its depth grows with WIDTH like ripple carry adder.
 */
module PriorityEncoder #(
    parameter  SIZE  = 3,
    localparam WIDTH = 1 << SIZE
)(
    input  wire [WIDTH-1:0] in,
    output wire [SIZE-1:0]  out,   // index of the highest bit set in in, 0 if none
    output wire             valid  // 1 if any bit of in is set
);
    localparam HALF = WIDTH / 2;

    // above[k]: some bit higher than k is set.
    // split_var: Verilator treats bits separately, no false loop through above.
    wire [WIDTH-1:0] above /*verilator split_var*/;
    // top[0] is not needed: index 0 has no bits set, it is in no OR of out.
    wire [WIDTH-1:1] above_n, top;

    assign above[WIDTH-1] = 1'b0;

    genvar k, j, m;
    generate
    for (k = 0; k < WIDTH-1; k = k + 1) begin: g_above
        Or2 #(1) u_or2(.in1(in[k+1]), .in2(above[k+1]), .out(above[k]));
    end
    endgenerate

    Inv  #(WIDTH-1) u_inv (.in(above[WIDTH-1:1]), .out(above_n));
    And2 #(WIDTH-1) u_and2(.in1(in[WIDTH-1:1]), .in2(above_n), .out(top));

    // out[j] is OR of top[k] for every k with bit j set.
    generate
    for (j = 0; j < SIZE; j = j + 1) begin: g_out
        wire [HALF-1:0] sel;
        for (m = 0; m < HALF; m = m + 1) begin: g_sel
            assign sel[m] = top[((m >> j) << (j+1)) | (1 << j) | (m & ((1 << j) - 1))];
        end
        OrReduce #(HALF) u_or_reduce(.in(sel), .out(out[j]));
    end
    endgenerate

    Or2 #(1) u_or2_valid(.in1(in[0]), .in2(above[0]), .out(valid));

endmodule
