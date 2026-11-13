/* Stream compaction: the valid elements of a row moved to its front, in order; made of
 * blocks, parts and gates.
 *
 * Same ports and results as the behave version. Every valid element moves down by the
 * number of invalid elements below it, its gap: then the valid ones sit at 0, 1, 2, ... in
 * their order. The gaps are a PrefixCount of the invalid elements. The move is a network of
 * LEVELS = log2(WIDTH) stages, as a barrel shifter's, but every element shifts by its own
 * amount: stage s moves an element down by 2^s when bit s of its gap is 1. The element
 * carries its gap with it, so a stage is a row of 2-input muxes, one per lane:
 *
 *   valid --> Inv --> PrefixCount --> gap[k] (invalid elements below k)
 *   lane k = {valid[k], gap[k], data[k]}
 *   stage s, lane j:  take the lane from j + 2^s if it is valid and its gap has bit s,
 *                     else keep lane j if it is valid and its gap has not bit s, else empty
 *   slots j < MAX: the last stage's lanes, data And-ed with valid; overflow: a valid lane
 *   at MAX or above; count = WIDTH - the invalid elements (PrefixCount's total)
 *
 * No two elements meet in a lane, and none passes another, when the stages go from the
 * smallest move to the largest: the gaps grow from element to element by the invalid ones
 * between them, so after the moves of bits below s two neighbours stay at least one lane
 * apart (their distance shrinks by at most the growth of the gap, modulo 2^s). So at most
 * one of "take" and "keep" holds in a lane and the mux needs no priority. For example,
 * gaps 1, 3, 3, 4 (elements at 1, 4, 5, 7 of 8):
 *
 *   start      . 1 . . 4 5 . 7
 *   stage 0    1 . . 4 5 . . 7      gaps with bit 0: 1, 3, 3 move by 1
 *   stage 1    1 4 5 . . . . 7      gaps with bit 1: 3, 3 move by 2
 *   stage 2    1 4 5 7 . . . .      gaps with bit 2: 4 moves by 4
 *
 * WIDTH x LEVELS muxes of the gap and the data, and the PrefixCount: it grows as
 * WIDTH log2(WIDTH), where every slot choosing among all elements would grow as WIDTH x MAX.
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

    localparam LEVELS = $clog2(WIDTH);
    localparam PW     = CW + DATA_WIDTH;        // what a lane carries besides valid

    wire [WIDTH-1:0]         invalid;           // ~valid
    wire [WIDTH-1:0][CW-1:0] gap;               // gap[k]: invalid elements below k
    wire [CW-1:0]            invalid_total;     // invalid elements
    wire [CW-1:0]            invalid_total_n;   // ~invalid_total, for WIDTH - invalid_total

    // Lanes before stage s: v[s][j] a valid element is in lane j, p[s][j] its {gap, data}.
    // split_var: Verilator treats the stages separately, no false loop.
    wire [WIDTH-1:0]         v [0:LEVELS] /*verilator split_var*/;
    wire [WIDTH-1:0][PW-1:0] p [0:LEVELS] /*verilator split_var*/;

    Inv #(WIDTH) u_inv(.in(valid), .out(invalid));
    PrefixCount #(WIDTH) u_prefix_count(.in(invalid), .prefix(gap), .total(invalid_total));

    // count = WIDTH - invalid_total = WIDTH + ~invalid_total + 1.
    Inv #(CW) u_inv_total(.in(invalid_total), .out(invalid_total_n));
    // The difference fits in CW bits: the carry out is not part of it.
    /* verilator lint_off UNUSEDSIGNAL */
    wire co;
    /* verilator lint_on UNUSEDSIGNAL */
    KoggeStoneAdder #(CW) u_kogge_stone_adder(
        .in1(CW'(WIDTH)), .in2(invalid_total_n), .ci(1'b1), .co, .sum(count));

    assign v[0] = valid;
    for (genvar k = 0; k < WIDTH; k++) begin : g_lane
        assign p[0][k] = {gap[k], data[k]};
    end

    // @kb: rtl/lib/block/stream_compact/design
    for (genvar s = 0; s < LEVELS; s++) begin : g_stage
        localparam S = 1 << s;                  // how far this stage moves an element
        for (genvar j = 0; j < WIDTH; j++) begin : g_lane
            wire move_n;                        // ~(bit s of lane j's gap)
            wire keep;                          // lane j's element stays

            Inv  #(1) u_inv(.in(p[s][j][DATA_WIDTH+s]), .out(move_n));
            And2 #(1) u_and2_keep(.in1(v[s][j]), .in2(move_n), .out(keep));
            if (j + S < WIDTH) begin : g_take
                wire take;                      // the element of lane j + S moves into j
                And2 #(1) u_and2_take(.in1(v[s][j+S]), .in2(p[s][j+S][DATA_WIDTH+s]),
                                      .out(take));
                Or2  #(1) u_or2(.in1(keep), .in2(take), .out(v[s+1][j]));
                Mux2 #(PW) u_mux2(.in0(p[s][j]), .in1(p[s][j+S]), .sel(take),
                                  .out(p[s+1][j]));
            end else begin : g_top
                assign v[s+1][j] = keep;
                assign p[s+1][j] = p[s][j];
            end
        end
    end

    for (genvar j = 0; j < MAX; j++) begin : g_slot
        assign out_valid[j] = v[LEVELS][j];
        And2 #(DATA_WIDTH) u_and2(.in1(p[LEVELS][j][DATA_WIDTH-1:0]),
                                  .in2({DATA_WIDTH{v[LEVELS][j]}}), .out(out_data[j]));
    end

    if (MAX < WIDTH) begin : g_overflow
        OrReduce #(WIDTH - MAX) u_or_reduce(.in(v[LEVELS][WIDTH-1:MAX]), .out(overflow));
    end else begin : g_no_overflow
        assign overflow = 1'b0;
    end

endmodule
