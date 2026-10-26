/* Branch target buffer (BTB), made of blocks and gates: remembers taken branches and jumps,
 * so that fetch can go to the target of a branch in the cycle it requests the branch.
 *
 * Same ports and behavior as the behave version (see there for the rules of lookup,
 * update and invalidate). Tags, targets and counters are unknown until written; only the
 * valid bits have a reset.
 *
 * The fields are in two RegFile blocks: tags with two read ports (lookup and invalidate),
 * targets with counters with one (lookup). RegFile, not Sram1R1W: the lookup must be
 * combinational, and the read of Sram1R1W is registered. The valid bits are DffSyncRst,
 * outside the RegFiles because they need the reset and a second write (the clear of an
 * invalidate). Comparators: CmpEq of tags for the lookup hit and the invalidate. The
 * update wins over an invalidate of the same entry by the order of the valid logic: clear,
 * then set; no comparator of the indexes is needed. The counter of an update is
 * the step of GshareBranchPredictor, bit by bit (BranchCounterPkg::update), with c1 c0
 * the bits of update_counter and t the outcome:
 *   new c1 = Maj3(c1,  c0, t): taken c1 | c0,  not taken c1 & c0
 *   new c0 = Maj3(c1, ~c0, t): taken c1 | ~c0, not taken c1 & ~c0
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module BranchTargetBuffer import BranchCounterPkg::*; #(
    parameter  INDEX_WIDTH  = 4,                // table of 1 << INDEX_WIDTH entries
    parameter  TAG_WIDTH    = 10,
    parameter  TARGET_WIDTH = 30,               // target as word address
    localparam PC_WIDTH     = INDEX_WIDTH + TAG_WIDTH
)(
    input  wire                    clk,
    input  wire                    rst_n,           // synchronous reset, active low

    // Lookup, combinational
    input  wire [PC_WIDTH-1:0]     lookup_pc,       // low bits of the pc as word address
    output wire                    lookup_hit,
    output wire                    lookup_taken,    // a hit whose counter says taken
    output wire [TARGET_WIDTH-1:0] lookup_target,
    output counter_e               lookup_counter,  // carried with hit to the update

    // Update: a conditional branch or a jump resolved; hit and counter of its lookup.
    input  wire                    update_en,
    input  wire [PC_WIDTH-1:0]     update_pc,
    input  wire                    update_hit,
    input  counter_e               update_counter,
    input  wire                    update_taken,
    input  wire [TARGET_WIDTH-1:0] update_target,   // target when taken, also when not taken

    // Invalidate: the entry of inval_pc predicted wrong.
    input  wire                    inval_en,
    input  wire [PC_WIDTH-1:0]     inval_pc
);
    localparam ENTRIES = 1 << INDEX_WIDTH;
    // As bits: Icarus 13 gets an enum constant wrong on a module port.
    localparam logic [1:0] WEAK_TAKEN = CNT_WEAK_TAKEN;

    wire [INDEX_WIDTH-1:0]  lookup_index;
    wire [INDEX_WIDTH-1:0]  update_index;
    wire [INDEX_WIDTH-1:0]  inval_index;
    wire [TAG_WIDTH-1:0]    lookup_tag;         // tag of the entry of lookup_pc
    wire [TAG_WIDTH-1:0]    inval_tag;          // tag of the entry of inval_pc
    wire [1:0]              counter;            // lookup_counter as bits
    wire [1:0]              counter_step;       // update_counter one step towards the outcome
    wire [1:0]              counter_new;        // counter written by the update
    wire                    c0_n;
    wire                    lookup_tag_eq;
    wire                    inval_tag_eq;
    wire                    update_hit_taken;
    wire                    update_write;       // write the entry of update_pc
    wire                    inval_clear;        // clear the entry of inval_pc
    wire [ENTRIES-1:0]      valid;
    wire [ENTRIES-1:0]      valid_kept;         // valid without the entry cleared
    wire [ENTRIES-1:0]      valid_next;
    wire [ENTRIES-1:0]      set_line;           // one-hot: the entry the update writes
    wire [ENTRIES-1:0]      clear_line;         // one-hot: the entry the invalidate clears
    wire [ENTRIES-1:0]      clear_line_n;
    wire [ENTRIES-1:0]      lookup_line;        // one-hot: the entry of lookup_pc
    wire [ENTRIES-1:0]      lookup_valid_line;
    wire                    lookup_valid;

    // Direct-mapped: the low bits of the pc pick the entry, the rest is its tag.
    assign lookup_index = lookup_pc[INDEX_WIDTH-1:0];
    assign update_index = update_pc[INDEX_WIDTH-1:0];
    assign inval_index  = inval_pc[INDEX_WIDTH-1:0];

    // Tags: the invalidate reads the tag of its entry in the same cycle as the lookup, so
    // a second read port, only for the tags.
    RegFile #(.RD_PORTS(2), .WR_PORTS(1), .ADDR_WIDTH(INDEX_WIDTH), .DATA_WIDTH(TAG_WIDTH))
        u_reg_file_tag(
            .clk(clk),
            .rd_addr({inval_index, lookup_index}), .rd_data({inval_tag, lookup_tag}),
            .wr_en(update_write), .wr_addr(update_index),
            .wr_data(update_pc[PC_WIDTH-1:INDEX_WIDTH]));

    // Targets with counters: the whole entry is written by every update (see behave).
    RegFile #(.RD_PORTS(1), .WR_PORTS(1), .ADDR_WIDTH(INDEX_WIDTH),
              .DATA_WIDTH(TARGET_WIDTH + 2))
        u_reg_file_target(
            .clk(clk),
            .rd_addr(lookup_index), .rd_data({lookup_target, counter}),
            .wr_en(update_write), .wr_addr(update_index),
            .wr_data({update_target, counter_new}));

    // Lookup: valid of the entry by its one-hot line, AND and OR, as a RegFile read.
    Decoder  #(.SIZE(INDEX_WIDTH)) u_decoder_lookup(.in(lookup_index), .en(1'b1),
                                                    .out(lookup_line));
    And2     #(ENTRIES) u_and2_lookup_valid(.in1(valid), .in2(lookup_line),
                                            .out(lookup_valid_line));
    OrReduce #(ENTRIES) u_or_reduce_lookup_valid(.in(lookup_valid_line), .out(lookup_valid));

    CmpEq #(TAG_WIDTH) u_cmp_eq_lookup(.in1(lookup_tag), .in2(lookup_pc[PC_WIDTH-1:INDEX_WIDTH]),
                                       .eq(lookup_tag_eq));
    And2  #(1) u_and2_hit(.in1(lookup_valid), .in2(lookup_tag_eq), .out(lookup_hit));
    // Taken: the high bit of the counter (the two taken states of counter_e).
    And2  #(1) u_and2_taken(.in1(lookup_hit), .in2(counter[1]), .out(lookup_taken));

    // Counter and target come out on a miss too: the user looks at them only with a hit.
    assign lookup_counter = counter_e'(counter);

    // Update: a hit or a taken miss writes; a not taken miss writes nothing (see behave).
    Or2  #(1) u_or2_update (.in1(update_hit), .in2(update_taken), .out(update_hit_taken));
    And2 #(1) u_and2_update(.in1(update_en), .in2(update_hit_taken), .out(update_write));

    // Counter of the update: a hit steps the carried counter, a new entry is weakly taken.
    Inv  #(1) u_inv   (.in(update_counter[0]), .out(c0_n));
    Maj3 #(1) u_maj3_1(.in1(update_counter[1]), .in2(update_counter[0]), .in3(update_taken),
                       .out(counter_step[1]));
    Maj3 #(1) u_maj3_0(.in1(update_counter[1]), .in2(c0_n), .in3(update_taken),
                       .out(counter_step[0]));
    Mux2 #(2) u_mux2_counter(.in0(WEAK_TAKEN), .in1(counter_step), .sel(update_hit),
                             .out(counter_new));

    // Invalidate: clears only when the entry still has the tag of inval_pc (see behave for
    // why).
    CmpEq #(TAG_WIDTH) u_cmp_eq_inval(.in1(inval_tag), .in2(inval_pc[PC_WIDTH-1:INDEX_WIDTH]),
                                      .eq(inval_tag_eq));
    And2  #(1) u_and2_inval(.in1(inval_en), .in2(inval_tag_eq), .out(inval_clear));

    // Valid bits: clear, then set, so that an update of the entry the invalidate clears wins.
    Decoder #(.SIZE(INDEX_WIDTH)) u_decoder_set  (.in(update_index), .en(update_write),
                                                  .out(set_line));
    Decoder #(.SIZE(INDEX_WIDTH)) u_decoder_clear(.in(inval_index), .en(inval_clear),
                                                  .out(clear_line));
    Inv  #(ENTRIES) u_inv_clear(.in(clear_line), .out(clear_line_n));
    And2 #(ENTRIES) u_and2_kept(.in1(valid), .in2(clear_line_n), .out(valid_kept));
    Or2  #(ENTRIES) u_or2_set  (.in1(valid_kept), .in2(set_line), .out(valid_next));

    DffSyncRst #(.WIDTH(ENTRIES)) u_dff_sync_rst(.clk(clk), .rst_n(rst_n), .in(valid_next),
                                                 .out(valid));

endmodule
