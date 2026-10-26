/* Test of BranchTargetBuffer.
 *
 * Random, the way fetch uses the block: every clock a lookup of a random pc; some lookups
 * are branches, whose hit and counter go with them to their update a few clocks later (up
 * to 3 in flight), with a random outcome and target; random invalidates, of the pc looked
 * up in the cycle before (as a check in ID would) or of any pc. The pcs have few tags per
 * index, so that entries are shared: hits, conflicts, stale hits (another branch took the
 * entry between the lookup and the update of one). A model of its own checks the lookup
 * in every cycle before the rising edge: hit and taken always, target and counter on a hit
 * (on a miss they are memory content, unknown at first in Icarus). One reset in the middle
 * clears the entries and keeps their content. In the end the test checks that every case
 * happened: hits taken and not taken, stale hits, not taken misses, invalidates that clear,
 * that find another tag, that lose to an update of the same entry.
 * Runs with two sizes, Mig2's (16 entries, tag 10, target 30) and a small one (4 entries,
 * tag 2, target 8): 20000 clocks on Verilator, 2000 on Icarus. Stops at the first mismatch
 * with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbBtbCheck import BranchCounterPkg::*; #(
    parameter INDEX_WIDTH  = 4,     // up to 8
    parameter TAG_WIDTH    = 10,    // 2 or more
    parameter TARGET_WIDTH = 30     // up to 32
)(
    input  wire  clk,
    output logic done
);
    localparam ENTRIES  = 1 << INDEX_WIDTH;
`ifdef VERILATOR
    localparam N_RANDOM = 20000;    // clocks of the random test
`else
    localparam N_RANDOM = 2000;
`endif
    localparam DEPTH    = 3;        // lookups in flight at most
    localparam TAGS     = 4;        // tags of the pcs: few, so that entries are shared

    typedef logic [INDEX_WIDTH-1:0]  index_t;
    typedef logic [TAG_WIDTH-1:0]    tag_t;
    typedef logic [TARGET_WIDTH-1:0] target_t;
    typedef struct packed {
        tag_t   tag;
        index_t index;
    } pc_t;                         // the pc as the block takes it apart

    logic     rst_n;
    pc_t      lookup_pc;
    wire      lookup_hit;
    wire      lookup_taken;
    target_t  lookup_target;
    counter_e lookup_counter;
    logic     update_en;
    pc_t      update_pc;
    logic     update_hit;
    counter_e update_counter;
    logic     update_taken;
    target_t  update_target;
    logic     inval_en;
    pc_t      inval_pc;

    // Model: the entries, 2-state; the counter as a count that saturates at 0 and 3.
    bit                    m_valid   [ENTRIES];
    bit [TAG_WIDTH-1:0]    m_tag     [ENTRIES];
    bit [TARGET_WIDTH-1:0] m_target  [ENTRIES];
    integer                m_counter [ENTRIES];

    // Lookups in flight, oldest at head: pc, hit and counter.
    pc_t      fl_pc      [DEPTH];
    logic     fl_hit     [DEPTH];
    counter_e fl_counter [DEPTH];
    integer   fl_n;

    tag_t     pool [TAGS];          // the tags of the pcs
    pc_t      last_pc;              // looked up in the cycle before
    integer   seed;

    // Cases seen.
    integer   n_hit_taken;
    integer   n_hit_not_taken;
    integer   n_stale;
    integer   n_miss_not_taken;
    integer   n_inval_clear;
    integer   n_inval_other_tag;
    integer   n_inval_lost;

    BranchTargetBuffer #(.INDEX_WIDTH(INDEX_WIDTH), .TAG_WIDTH(TAG_WIDTH),
                         .TARGET_WIDTH(TARGET_WIDTH)) u_branch_target_buffer(
        .clk, .rst_n, .lookup_pc, .lookup_hit, .lookup_taken, .lookup_target, .lookup_counter,
        .update_en, .update_pc, .update_hit, .update_counter, .update_taken, .update_target,
        .inval_en, .inval_pc);

    // Before the rising edge: the lookup of this cycle is that of the model.
    task automatic check_lookup;
        index_t i;
        logic   hit;
        logic   taken;
        i     = lookup_pc.index;
        hit   = m_valid[i] && m_tag[i] == lookup_pc.tag;
        taken = hit && m_counter[i] >= 2;
        if (lookup_hit !== hit || lookup_taken !== taken ||
            (hit && (lookup_target !== m_target[i] || lookup_counter !== m_counter[i][1:0])))
            $fatal(1, "Btb %0d: pc %h hit %b taken %b target %h counter %0d, expected %b %b %h %0d",
                   INDEX_WIDTH, lookup_pc, lookup_hit, lookup_taken, lookup_target,
                   lookup_counter, hit, taken, m_target[i], m_counter[i]);
        if (taken)
            n_hit_taken = n_hit_taken + 1;
        else if (hit)
            n_hit_not_taken = n_hit_not_taken + 1;
    endtask

    // Model of one rising edge with the inputs of this cycle.
    task automatic model_edge;
        index_t ui;
        index_t ii;
        integer c;
        logic   write;
        logic   clear;
        logic   lost;
        ui    = update_pc.index;
        ii    = inval_pc.index;
        write = update_en && (update_hit || update_taken);
        // The invalidate looks at the entry before the update writes it.
        clear = inval_en && m_valid[ii] && m_tag[ii] == inval_pc.tag;
        lost  = clear && write && ui == ii;
        if (update_en && update_hit && !(m_valid[ui] && m_tag[ui] == update_pc.tag))
            n_stale = n_stale + 1;
        if (update_en && !update_hit && !update_taken)
            n_miss_not_taken = n_miss_not_taken + 1;
        if (inval_en && m_valid[ii] && m_tag[ii] != inval_pc.tag)
            n_inval_other_tag = n_inval_other_tag + 1;
        if (lost)
            n_inval_lost = n_inval_lost + 1;
        else if (clear)
            n_inval_clear = n_inval_clear + 1;
        if (write) begin
            c = 2;                      // a new entry: weakly taken
            if (update_hit) begin
                c = 32'(update_counter);
                if (update_taken)
                    c = (c == 3) ? 3 : c + 1;
                else
                    c = (c == 0) ? 0 : c - 1;
            end
            m_tag[ui]     = update_pc.tag;
            m_target[ui]  = update_target;
            m_counter[ui] = c;
        end
        if (!rst_n) begin
            for (int i = 0; i < ENTRIES; i++)
                m_valid[i] = 1'b0;
        end else begin
            if (write)
                m_valid[ui] = 1'b1;
            if (clear && !lost)
                m_valid[ii] = 1'b0;
        end
    endtask

    task automatic random_test;
        // Bits of r: 0 branch, 1 update, 2 outcome, 3..4 invalidate, 5 of the last pc,
        // 6 of the entry of the update, 8 and up index of the lookup, 16..17 its tag,
        // 18..19 tag and 20 and up index of the invalidate; the rest unused.
        /* verilator lint_off UNUSEDSIGNAL */
        integer r;
        /* verilator lint_on UNUSEDSIGNAL */
        logic   push;
        fl_n = 0;
        for (int k = 0; k < N_RANDOM; k++) begin
            r         = $random(seed);
            rst_n     = (k != N_RANDOM / 2);
            lookup_pc.tag   = pool[r[17:16]];
            lookup_pc.index = r[8 +: INDEX_WIDTH];
            update_en = r[1] && fl_n > 0;
            if (update_en) begin
                update_pc      = fl_pc[0];
                update_hit     = fl_hit[0];
                update_counter = fl_counter[0];
                update_taken   = r[2];
                update_target  = TARGET_WIDTH'($random(seed));
                for (int i = 1; i < DEPTH; i++) begin
                    fl_pc[i-1]      = fl_pc[i];
                    fl_hit[i-1]     = fl_hit[i];
                    fl_counter[i-1] = fl_counter[i];
                end
                fl_n = fl_n - 1;
            end
            inval_en = r[4:3] == 2'b00;
            inval_pc.tag   = r[5] ? last_pc.tag : pool[r[19:18]];
            inval_pc.index = r[5] ? last_pc.index : r[20 +: INDEX_WIDTH];
            if (inval_en && update_en && r[6])      // the same entry: the update wins
                inval_pc.index = update_pc.index;
            push = r[0] && fl_n < DEPTH;
            #1;
            check_lookup();
            if (push) begin
                fl_pc[fl_n]      = lookup_pc;
                fl_hit[fl_n]     = lookup_hit;
                fl_counter[fl_n] = lookup_counter;
                fl_n = fl_n + 1;
            end
            last_pc = lookup_pc;
            model_edge();
            @(negedge clk);
        end
        rst_n     = 1'b1;
        update_en = 1'b0;
        inval_en  = 1'b0;
    endtask

    initial begin
        done = 1'b0;
        seed = INDEX_WIDTH;
        n_hit_taken       = 0;
        n_hit_not_taken   = 0;
        n_stale           = 0;
        n_miss_not_taken  = 0;
        n_inval_clear     = 0;
        n_inval_other_tag = 0;
        n_inval_lost      = 0;
        // Different tags, with random high bits.
        for (int t = 0; t < TAGS; t++)
            pool[t] = (TAG_WIDTH'($random(seed)) & ~TAG_WIDTH'(3)) | TAG_WIDTH'(t);
        last_pc        = '0;
        rst_n          = 1'b0;
        lookup_pc      = '0;
        update_en      = 1'b0;
        update_pc      = '0;
        update_hit     = 1'b0;
        update_counter = CNT_STRONG_NOT_TAKEN;
        update_taken   = 1'b0;
        update_target  = '0;
        inval_en       = 1'b0;
        inval_pc       = '0;
        // Reset: every entry invalid.
        @(negedge clk);
        model_edge();
        @(negedge clk);
        random_test();
        if (n_hit_taken == 0 || n_hit_not_taken == 0 || n_stale == 0 || n_miss_not_taken == 0 ||
            n_inval_clear == 0 || n_inval_other_tag == 0 || n_inval_lost == 0)
            $fatal(1, "Btb %0d: a case did not happen: hit %0d %0d, stale %0d, miss %0d, inval %0d %0d %0d",
                   INDEX_WIDTH, n_hit_taken, n_hit_not_taken, n_stale, n_miss_not_taken,
                   n_inval_clear, n_inval_other_tag, n_inval_lost);
        done = 1'b1;
    end
endmodule

module TbBranchTargetBuffer;
    wire clk;
    wire done_mig2;
    wire done_small;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbBtbCheck #(.INDEX_WIDTH(4), .TAG_WIDTH(10), .TARGET_WIDTH(30)) u_check_mig2(
        .clk, .done(done_mig2));
    TbBtbCheck #(.INDEX_WIDTH(2), .TAG_WIDTH(2), .TARGET_WIDTH(8)) u_check_small(
        .clk, .done(done_small));

    initial begin
        wait (done_mig2 && done_small);
        $display("PASS");
        $finish;
    end
endmodule
