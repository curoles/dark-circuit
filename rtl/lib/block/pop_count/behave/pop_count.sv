/* Population count, behavioral: count = number of ones in in, combinational.
 *
 * WIDTH is 1 or more, not only a power of 2; count has the bits for 0..WIDTH.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module PopCount #(
    parameter  WIDTH = 32,
    localparam CW    = $clog2(WIDTH + 1)    // bits of a count 0..WIDTH
)(
    input  wire [WIDTH-1:0] in,
    output wire [CW-1:0]    count           // number of ones in in
);
    // A function, not always_comb: Icarus warns about constant selects in always_* processes.
    function automatic [CW-1:0] ones(input [WIDTH-1:0] v);
        logic [CW-1:0] n;
        n = '0;
        for (int k = 0; k < WIDTH; k++)
            n = n + CW'(v[k]);
        return n;
    endfunction

    assign count = ones(in);

endmodule
