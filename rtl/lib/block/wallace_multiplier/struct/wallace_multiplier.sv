/* Wallace tree multiplier: product = a * b, unsigned, made of gates and parts.
 *
 * Same ports and result as CsaMultiplier. Partial product row j is a & b[j] (And2),
 * shifted left by j. Layers of CarrySaveAdders turn every three rows into two (sum and
 * carry, the carry shifted left by one); the 0..2 rows left over pass on to the next
 * layer. Rows per layer for WIDTH=32: 32, 22, 15, 10, 7, 5, 4, 3, 2: 8 layers, one full
 * adder deep each, instead of CsaMultiplier's 32 rows. A KoggeStoneAdder adds the last
 * two rows.
 *
 * - C. S. Wallace, A Suggestion for a Fast Multiplier, IEEE Transactions on Electronic
 *   Computers, 1964.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module WallaceMultiplier #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0]   a,
    input  wire [WIDTH-1:0]   b,
    output wire [2*WIDTH-1:0] product
);
    localparam P = 2 * WIDTH;

    // Rows left after k layers: every three rows become two, the rest pass on.
    function automatic int rows_after(int k);
        int n;
        n = WIDTH;
        for (int i = 0; i < k; i++)
            n = n / 3 * 2 + n % 3;
        return n;
    endfunction

    // Layers until at most two rows are left.
    function automatic int count_layers();
        int k;
        k = 0;
        while (rows_after(k) > 2)
            k++;
        return k;
    endfunction

    localparam LAYERS = count_layers();

    // row[k * WIDTH + j]: row j after k layers; layer k uses only its first rows_after(k)
    // entries, the others stay unused and undriven.
    /* verilator lint_off UNUSEDSIGNAL */
    /* verilator lint_off UNDRIVEN */
    wire [P-1:0] row [0:(LAYERS+1)*WIDTH-1] /*verilator split_var*/;
    /* verilator lint_on UNDRIVEN */
    /* verilator lint_on UNUSEDSIGNAL */

    // Partial products: row j = (a & b[j]) << j (a shift by a constant is wiring).
    for (genvar j = 0; j < WIDTH; j++) begin : g_pp
        wire [WIDTH-1:0] pp;        // a & b[j]
        wire [P-1:0]     pp_wide;   // pp in P bits
        And2 #(WIDTH) u_and2(.in1(a), .in2({WIDTH{b[j]}}), .out(pp));
        assign pp_wide = {{WIDTH{1'b0}}, pp};
        assign row[j]  = pp_wide << j;
    end

    // Layers: three rows into two; the rows left over pass on.
    for (genvar k = 0; k < LAYERS; k++) begin : g_layer
        localparam N      = rows_after(k);
        localparam GROUPS = N / 3;
        for (genvar g = 0; g < GROUPS; g++) begin : g_group
            // The top carry is always 0: the sum of the rows, a product, fits in P bits.
            /* verilator lint_off UNUSEDSIGNAL */
            wire [P-1:0] sc;
            /* verilator lint_on UNUSEDSIGNAL */
            CarrySaveAdder #(P) u_carry_save_adder(
                .in1(row[k*WIDTH + 3*g]), .in2(row[k*WIDTH + 3*g + 1]),
                .in3(row[k*WIDTH + 3*g + 2]), .ps(row[(k+1)*WIDTH + 2*g]), .sc);
            assign row[(k+1)*WIDTH + 2*g + 1] = {sc[P-2:0], 1'b0};
        end
        for (genvar t = 0; t < N % 3; t++) begin : g_pass
            assign row[(k+1)*WIDTH + 2*GROUPS + t] = row[k*WIDTH + 3*GROUPS + t];
        end
    end

    // The last two rows (one when WIDTH is 1) into the product.
    wire [P-1:0] last;              // second row, or 0
    // The product fits in P bits: no carry out.
    /* verilator lint_off UNUSEDSIGNAL */
    wire         co;
    /* verilator lint_on UNUSEDSIGNAL */
    if (rows_after(LAYERS) == 2) begin : g_two
        assign last = row[LAYERS*WIDTH + 1];
    end else begin : g_one
        assign last = '0;
    end
    KoggeStoneAdder #(P) u_kogge_stone_adder(
        .in1(row[LAYERS*WIDTH]), .in2(last), .ci(1'b0), .co, .sum(product));

endmodule
