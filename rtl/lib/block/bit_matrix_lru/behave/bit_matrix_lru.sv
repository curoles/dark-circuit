/* LRU replacement of a set of WAYS ways (a cache, a TLB, a BTB) by an age matrix,
 * combinational.
 *
 * The bits of the set (lru, WAYS * (WAYS - 1) / 2, see AgeMatrix) live in the user's RAM, one
 * entry per set: the user reads them with the set, gives them here, and writes lru_next back.
 * touch=1 (a hit or a fill of touch_way) makes the way the most recently used; lru_next = lru
 * while touch=0. victim_way, the way a fill replaces: the highest invalid way when one is
 * invalid, else the least recently used way.
 *
 * Invalid ways first, so the RAM needs no reset: a way becomes valid only by a fill, which
 * touches it; when every way is valid, every way was touched since they were invalid, and
 * the bits are the order of these touches whatever the RAM held before (AgeMatrix: touching
 * every entry once makes garbage an order). So a user must touch a way when it fills it, and
 * a way must not become valid otherwise. WAYS is at least 2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module BitMatrixLru #(
    parameter  WAYS      = 4,                       // at least 2
    localparam WAY_WIDTH = $clog2(WAYS),
    localparam LRU_WIDTH = WAYS * (WAYS - 1) / 2
)(
    input  wire [LRU_WIDTH-1:0] lru,                // bits of the set, from the user's RAM
    input  wire                 touch,              // a hit or a fill of touch_way
    input  wire [WAY_WIDTH-1:0] touch_way,
    output wire [LRU_WIDTH-1:0] lru_next,           // back into the RAM

    input  wire [WAYS-1:0]      valid,              // ways of the set that hold a line
    output wire [WAY_WIDTH-1:0] victim_way          // highest invalid way, else the LRU way
);
    wire [WAYS-1:0] lru_way;    // one-hot: the least recently used way

    AgeMatrix #(.SIZE(WAYS)) u_age_matrix(
        .ages(lru), .touch, .touch_index(touch_way), .ages_next(lru_next),
        .select_mask({WAYS{1'b1}}), .select_oldest(lru_way));

    // Index of the bit set in a one-hot vector: the OR of the indices of the set bits.
    function automatic [WAY_WIDTH-1:0] index_of(input [WAYS-1:0] one_hot);
        index_of = '0;
        for (int w = 0; w < WAYS; w++)
            if (one_hot[w])
                index_of = index_of | WAY_WIDTH'(w);
    endfunction

    // Highest way that is not valid (as PriorityEncoder in the struct version); 0 when every
    // way is valid (not used then).
    function automatic [WAY_WIDTH-1:0] highest_invalid(input [WAYS-1:0] v);
        highest_invalid = '0;
        for (int w = 0; w < WAYS; w++)
            if (!v[w])
                highest_invalid = WAY_WIDTH'(w);    // a higher way wins
    endfunction

    assign victim_way = (&valid) ? index_of(lru_way) : highest_invalid(valid);

endmodule
