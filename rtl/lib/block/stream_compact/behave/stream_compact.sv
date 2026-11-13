/* Stream compaction, behavioral: the valid elements of a row moved to its front, in order;
 * combinational.
 *
 * WIDTH elements come in, element k with data[k] when valid[k] is 1. The valid ones go out
 * in the first slots, keeping their order: out_data[j] is the data of the j-th valid element
 * (j from 0), out_valid[j] is 1 for j < count. There are MAX slots: count is the number of
 * valid elements (up to WIDTH), overflow is 1 when it is more than MAX, and then only the
 * first MAX go out. Empty slots have out_data 0. WIDTH is 1 or more, MAX 1 to WIDTH.
 *
 * For example, WIDTH = 8, MAX = 4, data[k] = k (positions):
 *   valid (element 0 first)  0 1 0 0 1 1 0 1
 *   out_data                 1 4 5 7      out_valid 1 1 1 1, count 4, overflow 0
 *
 * With data[k] = k it turns a bit vector into the list of its ones (zero suppression: the
 * hit channels of a detector, the detection events of a QEC round); with other data it
 * packs requests or packets that are present into a dense list.
 *
 * The behave version walks the elements from 0 up and appends every valid one. The struct
 * version moves every valid element down by the number of invalid ones below it, in
 * log2(WIDTH) stages of 2-input muxes.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module StreamCompact #(
    parameter  WIDTH      = 32,                 // elements in
    parameter  MAX        = 8,                  // slots out, 1 to WIDTH
    parameter  DATA_WIDTH = 5,                  // bits of an element's data
    localparam CW         = $clog2(WIDTH + 1)   // bits of a count 0..WIDTH
)(
    input  wire [WIDTH-1:0]                 valid,      // element k is present
    input  wire [WIDTH-1:0][DATA_WIDTH-1:0] data,       // its data
    output wire [MAX-1:0]                   out_valid,  // slot j holds an element: j < count
    output wire [MAX-1:0][DATA_WIDTH-1:0]   out_data,   // the j-th valid element's data, or 0
    output wire [CW-1:0]                    count,      // valid elements
    output wire                             overflow    // count > MAX: some did not go out
);
    `DC_STATIC_ASSERT(a_sizes, WIDTH >= 1 && MAX >= 1 && MAX <= WIDTH && DATA_WIDTH >= 1)

    // {count, out_data}: every valid element appended while there are slots.
    function automatic [CW+MAX*DATA_WIDTH-1:0] compact(input [WIDTH-1:0] vld,
                                                       input [WIDTH-1:0][DATA_WIDTH-1:0] d);
        logic [MAX-1:0][DATA_WIDTH-1:0] o;
        logic [CW-1:0]                  n;
        o = '0;
        n = '0;
        for (int k = 0; k < WIDTH; k++)
            if (vld[k]) begin
                if (int'(n) < MAX)
                    o[n] = d[k];
                n = n + 1'b1;
            end
        return {n, o};
    endfunction

    // Slot j is full when there are more than j valid elements.
    function automatic [MAX-1:0] full(input [CW-1:0] n);
        logic [MAX-1:0] f;
        for (int j = 0; j < MAX; j++)
            f[j] = int'(n) > j;
        return f;
    endfunction

    assign {count, out_data} = compact(valid, data);
    assign out_valid         = full(count);
    assign overflow          = int'(count) > MAX;

endmodule
