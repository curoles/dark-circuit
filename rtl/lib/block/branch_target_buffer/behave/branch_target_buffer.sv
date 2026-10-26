/* Branch target buffer (BTB): remembers taken branches and jumps, so that fetch can go to
 * the target of a branch in the cycle it requests the branch, before the instruction is
 * known.
 *
 * A direct-mapped table of 1 << INDEX_WIDTH entries; an entry is valid, tag, target and a
 * 2-bit counter for the direction (BranchCounterPkg). A pc (low PC_WIDTH bits of the word
 * address) picks entry pc[INDEX_WIDTH-1:0], which hits when valid with tag
 * pc[PC_WIDTH-1:INDEX_WIDTH]. When the user's pc has more bits than PC_WIDTH, pcs can share
 * an entry (aliasing): the user checks a prediction once it knows the instruction and
 * invalidates a wrong entry.
 *
 * Lookup is combinational: lookup_pc of this cycle gives lookup_hit, lookup_taken (a hit
 * whose counter says taken), lookup_target and lookup_counter. The user carries hit and
 * counter with the instruction to its update. Update, when a conditional branch or a jump
 * resolves, with update_target its target when taken (also for a branch not taken): a hit
 * writes the entry with the counter one step towards the outcome; a taken miss writes a
 * new entry, counter weakly taken; a not taken miss writes nothing. Invalidate clears the
 * entry of inval_pc when it holds the tag of inval_pc; an update of the same entry in the
 * same cycle wins. A lookup sees the writes of the earlier cycles. Reset clears the valid
 * bits; tags, targets and counters have no reset (in hardware they are a memory).
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

    // Only valid has a reset: an entry must not hit before it is written; the other fields
    // are memory and mean nothing while valid is 0.
    logic [ENTRIES-1:0]      valid;
    logic [TAG_WIDTH-1:0]    tag     [ENTRIES];
    logic [TARGET_WIDTH-1:0] target  [ENTRIES];
    counter_e                counter [ENTRIES];

    logic [INDEX_WIDTH-1:0]  lookup_index;
    logic [INDEX_WIDTH-1:0]  update_index;
    logic [INDEX_WIDTH-1:0]  inval_index;
    logic                    update_write;      // write the entry of update_pc
    logic                    inval_clear;       // clear the entry of inval_pc

    // Direct-mapped: the low bits of the pc pick the entry, the rest is its tag. Branches
    // close to each other get different entries.
    assign lookup_index = lookup_pc[INDEX_WIDTH-1:0];
    assign update_index = update_pc[INDEX_WIDTH-1:0];
    assign inval_index  = inval_pc[INDEX_WIDTH-1:0];

    // The tag tells which of the pcs that share the entry wrote it.
    assign lookup_hit     = valid[lookup_index] &&
                            tag[lookup_index] == lookup_pc[PC_WIDTH-1:INDEX_WIDTH];
    // Counter and target come out on a miss too, without a mux to clear them: the user
    // looks at them only with lookup_hit, and the update ignores the counter of a miss.
    assign lookup_counter = counter[lookup_index];
    // A branch that learned not taken keeps its entry, but fetch goes on to the next pc.
    assign lookup_taken   = lookup_hit && counter_taken(lookup_counter);
    assign lookup_target  = target[lookup_index];

    // A not taken miss writes nothing: fetch already went on to the next pc, as without an
    // entry, and a new entry could only evict one that saves cycles.
    assign update_write = update_en && (update_hit || update_taken);
    // The tag check: by now the entry may belong to another branch (an update came in
    // between), which must stay. An update of the same entry in the same cycle wins over the
    // invalidate by the order of the valid writes below.
    assign inval_clear  = inval_en && tag[inval_index] == inval_pc[PC_WIDTH-1:INDEX_WIDTH];

    // The whole entry, tag and target also on a hit: the carried hit can be stale (another
    // branch with the same index took the entry between the lookup and the update of this
    // one); writing all fields takes the entry back whole, no fields of two branches mixed.
    // Hence update_target also for a branch not taken. A hit steps the counter of its
    // lookup, carried with the instruction: no second read port for the update. A new entry
    // starts weakly taken: the branch was just taken, and one not taken turns it off.
    always_ff @(posedge clk)
        if (update_write) begin
            tag[update_index]    <= update_pc[PC_WIDTH-1:INDEX_WIDTH];
            target[update_index] <= update_target;
            if (update_hit) counter[update_index] <= update(update_counter, update_taken);
            else            counter[update_index] <= CNT_WEAK_TAKEN;
        end

    always_ff @(posedge clk)
        if (!rst_n)
            valid <= '0;
        else begin
            // =====================================================================
            // !!! ORDER MATTERS: CLEAR FIRST, SET LAST. DO NOT SWAP THESE LINES !!!
            // =====================================================================
            // An update and an invalidate of the same entry in the same cycle both
            // write valid[i]; the last nonblocking assignment wins, and the update
            // must win: it comes from an older instruction and writes an entry that
            // is right, while the invalidate judged the entry before the update.
            // The struct version has the same order in gates: (valid & ~clear) | set.
            if (inval_clear)  valid[inval_index]  <= 1'b0;
            if (update_write) valid[update_index] <= 1'b1;
        end

endmodule
