/* LRU replacement of a set of WAYS ways (a cache, a TLB, a BTB) by an age matrix,
 * combinational, made of blocks and gates.
 *
 * Same ports and behavior as the behave version, see there. AgeMatrix with the mask of all
 * ways gives the touch (lru_next) and the least recently used way, one-hot: PriorityEncoder
 * makes it an index (its highest bit is its only one). PriorityEncoder of the inverted valid
 * bits gives the highest invalid way, and its valid output, some way is invalid, selects it
 * (Mux2) over the LRU way. Below a power of 2 the encoders' inputs are padded with 0.
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
    localparam WAYS_POW2 = 1 << WAY_WIDTH;          // ways rounded up to a power of 2

    wire [WAYS-1:0]      lru_way;       // one-hot: the least recently used way
    wire [WAYS_POW2-1:0] lru_way_pow2;
    wire [WAY_WIDTH-1:0] lru_index;
    wire [WAYS-1:0]      invalid;
    wire [WAYS_POW2-1:0] invalid_pow2;
    wire [WAY_WIDTH-1:0] invalid_index; // highest invalid way
    wire                 any_invalid;
    // Not used: some way is the LRU way (lru_way is one-hot when every way is valid).
    /* verilator lint_off UNUSEDSIGNAL */
    wire                 lru_valid;
    /* verilator lint_on UNUSEDSIGNAL */

    AgeMatrix #(.SIZE(WAYS)) u_age_matrix(
        .ages(lru), .touch, .touch_index(touch_way), .ages_next(lru_next),
        .select_mask({WAYS{1'b1}}), .select_oldest(lru_way));

    assign lru_way_pow2 = WAYS_POW2'(lru_way);
    PriorityEncoder #(.SIZE(WAY_WIDTH)) u_priority_encoder_lru(
        .in(lru_way_pow2), .out(lru_index), .valid(lru_valid));

    Inv #(WAYS) u_inv_valid(.in(valid), .out(invalid));
    assign invalid_pow2 = WAYS_POW2'(invalid);
    PriorityEncoder #(.SIZE(WAY_WIDTH)) u_priority_encoder_invalid(
        .in(invalid_pow2), .out(invalid_index), .valid(any_invalid));

    Mux2 #(WAY_WIDTH) u_mux2_victim(.in0(lru_index), .in1(invalid_index), .sel(any_invalid),
                                    .out(victim_way));

endmodule
