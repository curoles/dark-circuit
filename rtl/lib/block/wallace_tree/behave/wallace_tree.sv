/* Wallace tree: ROWS numbers reduced to two, sum + carry = sum of the rows (mod
 * 2^WIDTH), behavioral.
 *
 * Same ports as the struct version, and the same sum + carry; here the simulator adds,
 * sum is the total and carry is 0 (the struct version splits the total differently).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module WallaceTree #(
    parameter ROWS  = 3,
    parameter WIDTH = 64
)(
    input  wire [WIDTH-1:0] rows [ROWS],    // the numbers to add
    output wire [WIDTH-1:0] sum,
    output wire [WIDTH-1:0] carry           // sum + carry = sum of the rows, mod 2^WIDTH
);
    logic [WIDTH-1:0] total;                // sum of the rows, mod 2^WIDTH

    always_comb begin
        total = '0;
        for (int i = 0; i < ROWS; i++)
            total = total + rows[i];
    end

    assign sum   = total;
    assign carry = '0;

endmodule
