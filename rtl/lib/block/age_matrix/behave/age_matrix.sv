/* Age matrix: the order of SIZE entries from the newest to the oldest, combinational.
 *
 * The state (ages) lives outside, in registers or in a RAM (one per set of a cache): this
 * block computes the next state and the selection from it. For every pair of entries i < j
 * one bit says which of the two is newer: 1: i is newer than j, 0: j is newer than i. The
 * lower half of the matrix is the opposite of the upper one and the diagonal is 0, so only
 * the upper triangle is kept: SIZE * (SIZE - 1) / 2 bits, row by row (the bit of (i, j) at
 * i * SIZE - i * (i + 1) / 2 + j - i - 1).
 *
 * Touch: touch=1 makes entry touch_index the newest (a cache hit or fill, an entry of a
 * scheduler allocated): its row becomes 1 (newer than every other entry) and its column 0;
 * the order of the others stays. ages_next = ages while touch=0.
 * Select: select_oldest is one-hot, the oldest entry of select_mask (all ones: the least
 * recently touched entry; the ready entries of a scheduler: the oldest ready one); 0 when
 * select_mask is 0.
 *
 * All zeros is an order: entry SIZE-1 the newest, entry 0 the oldest (reset). Other states
 * are orders when they come from one by touches. Garbage (a RAM not written yet) may hold
 * cycles, and then select_oldest may be 0 or not one-hot; touching every entry once makes
 * it an order again: the order of the touches. SIZE is at least 2.
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
    // Bit of the pair (i, j), i < j, in ages.
    function automatic integer pos(input integer i, input integer j);
        return i * SIZE - i * (i + 1) / 2 + j - i - 1;
    endfunction

    // 1 when entry i is newer than entry j; 0 for i = j.
    function automatic logic newer(input [AGES_WIDTH-1:0] a, input integer i, input integer j);
        if (i < j)
            return a[pos(i, j)];
        if (i > j)
            return !a[pos(j, i)];
        return 1'b0;
    endfunction

    // The row of t becomes 1 and its column 0: in the triangle, the bits of the pairs with t
    // say "t is newer"; the bits of the other pairs keep the order of the others.
    function automatic [AGES_WIDTH-1:0] touched(input [AGES_WIDTH-1:0]  a,
                                                input [INDEX_WIDTH-1:0] t);
        integer ti;
        ti      = int'(t);
        touched = a;
        for (int i = 0; i < SIZE; i++)
            for (int j = i + 1; j < SIZE; j++)
                if (i == ti)
                    touched[pos(i, j)] = 1'b1;      // t = i is newer than j
                else if (j == ti)
                    touched[pos(i, j)] = 1'b0;      // t = j is newer than i
    endfunction

    // Entry i is the oldest of the mask when it is in the mask and newer than no other entry
    // of the mask.
    function automatic [SIZE-1:0] oldest(input [AGES_WIDTH-1:0] a, input [SIZE-1:0] mask);
        for (int i = 0; i < SIZE; i++) begin
            oldest[i] = mask[i];
            for (int j = 0; j < SIZE; j++)
                if (mask[j] && newer(a, i, j))
                    oldest[i] = 1'b0;
        end
    endfunction

    assign ages_next     = touch ? touched(ages, touch_index) : ages;
    assign select_oldest = oldest(ages, select_mask);

endmodule
