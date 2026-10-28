/* Age matrix: the order of SIZE entries from the newest to the oldest, combinational, made
 * of blocks and gates.
 *
 * Same ports and behavior as the behave version, see there. Touch: Decoder turns touch_index
 * into one line per entry (all 0 when touch=0); the bit of a pair (i, j) becomes
 * t_i | (bit & ~t_j): 1 when i is touched, 0 when j is, else it stays (And2, Or2 over all
 * pairs). Select: the row of entry i says which entries i is newer than: the bit of (i, j)
 * for j > i, the inverted bit of (j, i) for j < i (wires and one Inv over all bits); entry i
 * is the oldest of the mask when it is in the mask and its row ANDed with the mask is all 0
 * (And2, NorReduce).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module AgeMatrix #(
    parameter  SIZE        = 8,                     // entries, at least 2
    localparam INDEX_WIDTH = $clog2(SIZE),
    localparam AGES_WIDTH  = SIZE * (SIZE - 1) / 2  // the upper triangle of the matrix
)(
    input  wire [AGES_WIDTH-1:0]  ages,             // the order now
    input  wire                   touch,
    input  wire [INDEX_WIDTH-1:0] touch_index,      // becomes the newest when touch=1
    output wire [AGES_WIDTH-1:0]  ages_next,

    input  wire [SIZE-1:0]        select_mask,      // entries to select from
    output wire [SIZE-1:0]        select_oldest     // one-hot: the oldest of select_mask
);
    localparam DEC_WIDTH = 1 << INDEX_WIDTH;

    // Only the first SIZE lines are used: below a power of 2, no index reaches the others.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [DEC_WIDTH-1:0]  touch_dec;    // one-hot: the entry touched; 0 when touch=0
    /* verilator lint_on UNUSEDSIGNAL */
    wire [SIZE-1:0]       t;            // touch line of every entry
    wire [SIZE-1:1]       t_n;          // entry 0 is never the j of a pair
    wire [AGES_WIDTH-1:0] ages_n;
    wire [AGES_WIDTH-1:0] t_i;          // per pair (i, j): the touch line of i
    wire [AGES_WIDTH-1:0] t_n_j;        // per pair (i, j): the inverted touch line of j
    wire [AGES_WIDTH-1:0] kept;         // the bit, unless j is touched
    wire [SIZE-1:0]       free;         // per entry: newer than no entry of the mask

    // Bit of the pair (i, j), i < j, in ages (the wiring; computed at elaboration).
    function automatic integer pos(input integer i, input integer j);
        return i * SIZE - i * (i + 1) / 2 + j - i - 1;
    endfunction

    Decoder #(.SIZE(INDEX_WIDTH)) u_decoder(.in(touch_index), .en(touch), .out(touch_dec));
    assign t = touch_dec[SIZE-1:0];
    Inv #(SIZE-1)     u_inv_t(.in(t[SIZE-1:1]), .out(t_n));
    Inv #(AGES_WIDTH) u_inv_ages(.in(ages), .out(ages_n));

    // Touch: the lines of i and j in the place of every pair, then one gate per bit.
    for (genvar i = 0; i < SIZE; i++) begin: g_pair_row
        for (genvar j = i + 1; j < SIZE; j++) begin: g_pair
            assign t_i[pos(i, j)]   = t[i];
            assign t_n_j[pos(i, j)] = t_n[j];
        end
    end
    And2 #(AGES_WIDTH) u_and2_kept(.in1(ages), .in2(t_n_j), .out(kept));
    Or2  #(AGES_WIDTH) u_or2_next(.in1(t_i), .in2(kept), .out(ages_next));

    // Select: per entry its row of the full matrix, masked; free when nothing is left.
    for (genvar i = 0; i < SIZE; i++) begin: g_row
        wire [SIZE-1:0] newer;          // newer[j]: entry i is newer than entry j
        wire [SIZE-1:0] newer_masked;

        for (genvar j = 0; j < SIZE; j++) begin: g_col
            if (j > i) begin: g_upper
                assign newer[j] = ages[pos(i, j)];
            end else if (j < i) begin: g_lower
                assign newer[j] = ages_n[pos(j, i)];
            end else begin: g_diagonal
                assign newer[j] = 1'b0;
            end
        end
        And2      #(SIZE) u_and2_masked(.in1(newer), .in2(select_mask), .out(newer_masked));
        NorReduce #(SIZE) u_nor_reduce(.in(newer_masked), .out(free[i]));
    end
    And2 #(SIZE) u_and2_oldest(.in1(select_mask), .in2(free), .out(select_oldest));

endmodule
