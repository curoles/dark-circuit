/* Priority encoder 2**SIZE to SIZE, behavioral:
 * out is index of the highest bit set in in, valid is 1 if any bit of in is set;
 * out and valid are 0 when in is 0.
 *
 * For example, 8 to 3 priority encoder:
 *   8'b1xxxxxxx: out = 7
 *   8'b01xxxxxx: out = 6
 *   ...
 *   8'b00000001: out = 0
 *   8'b00000000: out = 0, valid = 0
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module PriorityEncoder #(
    parameter  SIZE  = 3,
    localparam WIDTH = 1 << SIZE
)(
    input  wire [WIDTH-1:0] in,
    output wire [SIZE-1:0]  out,   // index of the highest bit set in in, 0 if none
    output wire             valid  // 1 if any bit of in is set
);
    // Index of the highest bit set in v, 0 if none. A function, not always_comb:
    // Icarus warns about the constant select k[SIZE-1:0] in always_* processes.
    function automatic [SIZE-1:0] highest(input [WIDTH-1:0] v);
        highest = {SIZE{1'b0}};
        for (int k = 0; k < WIDTH; k = k + 1)
            if (v[k])
                highest = k[SIZE-1:0];  // later, higher bit wins
    endfunction

    assign out   = highest(in);
    assign valid = |in;

endmodule
