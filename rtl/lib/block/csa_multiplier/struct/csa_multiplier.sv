/* Carry-save array multiplier: product = a * b, unsigned, made of gates and parts.
 *
 * Partial product row i is a & b[i] (And2), weight 2^i. Row i of adders adds it to the
 * sums and carries of row i - 1: carries are saved for the next row, not propagated
 * along the row, so a row is one full adder deep. Bit i of the product is the lowest
 * sum of row i. The last row leaves two numbers, its sums and its carries: a
 * RippleCarryAdder adds them into the upper half of the product.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module CsaMultiplier #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0]   a,
    input  wire [WIDTH-1:0]   b,
    output wire [2*WIDTH-1:0] product
);
    wire [WIDTH-1:0] p_prod     [WIDTH-1:0];   // p_prod[i][j] = a[j] & b[i], weight 2^(i+j)
    wire [WIDTH-1:0] sum_grid   [WIDTH-1:0];   // sum of row i, column j: weight 2^(i+j)
    wire [WIDTH-1:0] carry_grid [WIDTH-1:0];   // carry of row i, column j: weight 2^(i+j+1)
    wire [WIDTH-1:0] last_sum;                 // sums of the last row above its column 0
    wire [WIDTH-1:0] last_carry;               // carries of the last row
    // The product fits in 2*WIDTH bits: the final adder has no carry out.
    /* verilator lint_off UNUSEDSIGNAL */
    wire             last_co;
    /* verilator lint_on UNUSEDSIGNAL */

    genvar i;
    genvar j;

    // Partial products.
    for (i = 0; i < WIDTH; i = i + 1) begin: g_pp_row
        And2 #(WIDTH) u_and2(.in1(a), .in2({WIDTH{b[i]}}), .out(p_prod[i]));
    end

    // Row 0 is the first partial product, without carries.
    assign sum_grid[0]   = p_prod[0];
    assign carry_grid[0] = '0;

    // Rows 1 and up: the column of weight 2^(i+j) adds the partial product bit, the sum
    // of row i - 1 at column j + 1 and the carry of row i - 1 at column j. The top
    // column has no sum above it.
    for (i = 1; i < WIDTH; i = i + 1) begin: g_row
        for (j = 0; j < WIDTH; j = j + 1) begin: g_col
            if (j == WIDTH - 1) begin: g_top
                HalfAdder #(1) u_half_adder(
                    .in1(carry_grid[i-1][j]), .in2(p_prod[i][j]),
                    .sum(sum_grid[i][j]), .co(carry_grid[i][j]));
            end else begin: g_inner
                FullAdder #(1) u_full_adder(
                    .in1(sum_grid[i-1][j+1]), .in2(p_prod[i][j]), .ci(carry_grid[i-1][j]),
                    .sum(sum_grid[i][j]), .co(carry_grid[i][j]));
            end
        end
    end

    // Lower half: the lowest sum of every row.
    for (i = 0; i < WIDTH; i = i + 1) begin: g_low
        assign product[i] = sum_grid[i][0];
    end

    // Upper half: sums of the last row (weight 2^(WIDTH+j-1), j >= 1) plus its carries
    // (weight 2^(WIDTH+j)).
    for (j = 1; j < WIDTH; j = j + 1) begin: g_last_sum
        assign last_sum[j-1] = sum_grid[WIDTH-1][j];
    end
    assign last_sum[WIDTH-1] = 1'b0;
    assign last_carry        = carry_grid[WIDTH-1];

    RippleCarryAdder #(.WIDTH(WIDTH)) u_ripple_carry_adder(
        .in1(last_sum), .in2(last_carry), .ci(1'b0), .co(last_co),
        .sum(product[2*WIDTH-1:WIDTH]));

endmodule
