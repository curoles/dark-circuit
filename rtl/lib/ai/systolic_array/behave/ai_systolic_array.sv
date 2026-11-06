module AiSystolicArray #(
    parameter int ROWS = 16,
    parameter int COLS = 16,
    parameter int DATA_W = 8,
    parameter int ACCUM_W = 32
)(
    input  logic clk,
    input  logic rst_n,
    input  logic [ROWS-1:0][DATA_W-1:0] left_inputs,
    input  logic [COLS-1:0][DATA_W-1:0] top_inputs,
    output logic [ROWS-1:0][COLS-1:0][ACCUM_W-1:0] array_outputs
);

    // 2D wire arrays to connect neighbor PEs together
    logic [ROWS-1:0][COLS:0][DATA_W-1:0] horiz_wires;
    logic [ROWS:0][COLS-1:0][DATA_W-1:0] vert_wires;

    // Hook up external inputs to the boundary wires
    assign horiz_wires[ROWS-1:0][0] = left_inputs;
    assign vert_wires[0][COLS-1:0]  = top_inputs;

    // Generate block physically stitches the PEs together
    genvar r, c;
    generate
        for (r = 0; r < ROWS; r++) begin : row_gen
            for (c = 0; c < COLS; c++) begin : col_gen
                // The PE is hardcoded to be an AI MAC, but perfectly parameterized
                AiMacPe #(
                    .DATA_W(DATA_W),
                    .ACCUM_W(ACCUM_W)
                ) u_pe (
                    .clk(clk),
                    .rst_n(rst_n),
                    .in_west(horiz_wires[r][c]),      // Data from left neighbor
                    .in_north(vert_wires[r][c]),     // Data from top neighbor
                    .out_east(horiz_wires[r][c+1]),   // Pass to right neighbor
                    .out_south(vert_wires[r+1][c]),  // Pass to bottom neighbor
                    .accum_out(array_outputs[r][c])
                );
            end
        end
    endgenerate

endmodule

