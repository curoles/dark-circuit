/* Multiplexer of N inputs by a one-hot select, made of gates.
 *
 * Same ports and behavior as the behave version (see there). Per bit of out: the bit of
 * every input (a column) And2 with sel, then OrReduce, as a RegFile read port.
 *
 *   column b = {in[N-1][b], ..., in[0][b]} --And2 sel--> selected --OrReduce--> out[b]
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module MuxOneHot #(
    parameter N     = 4,                    // inputs
    parameter WIDTH = 1                     // bits of an input
)(
    input  wire [N-1:0][WIDTH-1:0] in,      // input k: in[k]
    input  wire [N-1:0]            sel,     // sel[k]: input k is selected
    output wire [WIDTH-1:0]        out
);
    `DC_STATIC_ASSERT(a_inputs, N >= 1 && WIDTH >= 1)

    // @kb: rtl/lib/block/mux_one_hot/design
    for (genvar b = 0; b < WIDTH; b++) begin: g_bit
        wire [N-1:0] column;    // bit b of every input
        wire [N-1:0] selected;  // of the selected inputs
        for (genvar k = 0; k < N; k++) begin: g_in
            assign column[k] = in[k][b];
        end
        And2     #(N) u_and2     (.in1(column), .in2(sel), .out(selected));
        OrReduce #(N) u_or_reduce(.in(selected), .out(out[b]));
    end

endmodule
