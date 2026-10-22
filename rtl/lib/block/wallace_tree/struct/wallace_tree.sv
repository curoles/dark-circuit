/* Wallace tree: ROWS numbers reduced to two, sum + carry = sum of the rows (mod
 * 2^WIDTH), made of parts.
 *
 * Layers of CarrySaveAdders turn every three rows into two (the partial sum, and the
 * carries shifted left by one; the carry out of the top bit is dropped: mod 2^WIDTH);
 * the 0..2 rows left over pass on to the next layer, until two are left. Every layer is
 * one full adder deep: 32 rows take 8 layers (32, 22, 15, 10, 7, 5, 4, 3, 2), and so do
 * 35. An adder (KoggeStoneAdder) adds sum and carry for the total.
 *
 * - C. S. Wallace, A Suggestion for a Fast Multiplier, IEEE Transactions on Electronic
 *   Computers, 1964.
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
    // Rows left after k layers: every three rows become two, the rest pass on.
    function automatic int rows_after(int k);
        int n;
        n = ROWS;
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

    // row[k * ROWS + j]: row j after k layers; layer k uses only its first rows_after(k)
    // entries, the others stay unused and undriven.
    /* verilator lint_off UNUSEDSIGNAL */
    /* verilator lint_off UNDRIVEN */
    wire [WIDTH-1:0] row [0:(LAYERS+1)*ROWS-1] /*verilator split_var*/;
    /* verilator lint_on UNDRIVEN */
    /* verilator lint_on UNUSEDSIGNAL */

    for (genvar j = 0; j < ROWS; j++) begin : g_in
        assign row[j] = rows[j];
    end

    // Layers: three rows into two; the rows left over pass on.
    for (genvar k = 0; k < LAYERS; k++) begin : g_layer
        localparam N      = rows_after(k);
        localparam GROUPS = N / 3;
        for (genvar g = 0; g < GROUPS; g++) begin : g_group
            // The top carry has weight 2^WIDTH: dropped, the sum is mod 2^WIDTH.
            /* verilator lint_off UNUSEDSIGNAL */
            wire [WIDTH-1:0] sc;
            /* verilator lint_on UNUSEDSIGNAL */
            CarrySaveAdder #(WIDTH) u_carry_save_adder(
                .in1(row[k*ROWS + 3*g]), .in2(row[k*ROWS + 3*g + 1]),
                .in3(row[k*ROWS + 3*g + 2]), .ps(row[(k+1)*ROWS + 2*g]), .sc);
            assign row[(k+1)*ROWS + 2*g + 1] = {sc[WIDTH-2:0], 1'b0};
        end
        for (genvar t = 0; t < N % 3; t++) begin : g_pass
            assign row[(k+1)*ROWS + 2*GROUPS + t] = row[k*ROWS + 3*GROUPS + t];
        end
    end

    // The last two rows (one when ROWS is 1).
    assign sum = row[LAYERS*ROWS];
    if (rows_after(LAYERS) == 2) begin : g_two
        assign carry = row[LAYERS*ROWS + 1];
    end else begin : g_one
        assign carry = '0;
    end

endmodule
