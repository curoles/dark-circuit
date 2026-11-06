/* Systolic array of ROWS x COLS processing elements (AiMacPe), a sketch.
 *
 * Every PE takes an operand from its west and one from its north neighbor, passes them on
 * to east and south, and keeps an accumulator (accum_out): output stationary, the result of
 * PE (r, c) stays in it. Row r's operands enter at the west edge (left_inputs[r]), column
 * c's at the north edge (top_inputs[c]); the operands that leave the east and south edges
 * are not used.
 *
 *   top_inputs[0]   top_inputs[1]
 *        |               |
 *        v               v
 *      +----+  east    +----+
 *   -->| PE |--------->| PE |--> (not used)      left_inputs[0] enters row 0
 *      +----+          +----+
 *        | south         |
 *        v               v
 *      +----+          +----+
 *   -->| PE |--------->| PE |--> (not used)      left_inputs[1] enters row 1
 *      +----+          +----+
 *        |               |
 *        v               v
 *    (not used)      (not used)
 *
 * The PE, AiMacPe, is not written yet.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

module AiSystolicArray #(
    parameter ROWS       = 16,
    parameter COLS       = 16,
    parameter DATA_WIDTH = 8,                               // bits of an operand
    parameter ACC_WIDTH  = 32                               // bits of an accumulator
)(
    input  wire                                     clk,
    input  wire                                     rst_n,  // synchronous reset, active low
    input  wire  [ROWS-1:0][DATA_WIDTH-1:0]         left_inputs,    // into row r, west
    input  wire  [COLS-1:0][DATA_WIDTH-1:0]         top_inputs,     // into column c, north
    output wire  [ROWS-1:0][COLS-1:0][ACC_WIDTH-1:0] array_outputs  // accumulator of PE (r, c)
);
    // The operands between neighbors: horiz_wires[r][c] into PE (r, c) from the west,
    // vert_wires[r][c] from the north; the last column and row leave the array, not used.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [ROWS-1:0][COLS:0][DATA_WIDTH-1:0] horiz_wires;
    wire [ROWS:0][COLS-1:0][DATA_WIDTH-1:0] vert_wires;
    /* verilator lint_on UNUSEDSIGNAL */

    assign vert_wires[0] = top_inputs;

    for (genvar r = 0; r < ROWS; r++) begin: g_row
        assign horiz_wires[r][0] = left_inputs[r];
        for (genvar c = 0; c < COLS; c++) begin: g_col
            AiMacPe #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) u_pe(
                .clk, .rst_n,
                .in_west(horiz_wires[r][c]),
                .in_north(vert_wires[r][c]),
                .out_east(horiz_wires[r][c + 1]),
                .out_south(vert_wires[r + 1][c]),
                .accum_out(array_outputs[r][c]));
        end
    end

endmodule
