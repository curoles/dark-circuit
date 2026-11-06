/* Test of PlicClaim, behave or struct version.
 *
 * Model, from the contexts' side (the behave version loops over the sources): for every
 * context that claims, the bit of its claim ID is set, unless the ID is 0 or above
 * N_SOURCES; for every context that completes, the bit of its ID likewise, and only when
 * the ID is enabled for that context. Directed cases, then random inputs (IDs of every
 * value, also 0 and above N_SOURCES): 3000 on Verilator, 300 on Icarus. Every case must
 * happen (checks named cover): a claim, a complete, a complete dropped because its source is
 * not enabled for the context, ID 0, an ID above N_SOURCES (when IDs can be), two contexts
 * on the same source in one cycle (with two or more contexts). Checks named model and cover.
 * Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbPlicClaimCheck #(
    parameter N_SOURCES  = 7,
    parameter N_CONTEXTS = 2
)(
    output logic done
);
`ifdef VERILATOR
    localparam N_RANDOM = 3000;
`else
    localparam N_RANDOM = 300;
`endif
    localparam IDW       = $clog2(N_SOURCES + 1);
    localparam OUT_RANGE = (1 << IDW) > N_SOURCES + 1;  // some IDs belong to no source

    logic [N_CONTEXTS-1:0]              claim_en;
    logic [N_CONTEXTS-1:0][IDW-1:0]     claim_id;
    logic [N_CONTEXTS-1:0]              complete_en;
    logic [N_CONTEXTS-1:0][IDW-1:0]     complete_id;
    logic [N_CONTEXTS-1:0][N_SOURCES:0] ie;
    wire  [N_SOURCES:0]                 claim;
    wire  [N_SOURCES:0]                 complete;
    integer                             seed;
    logic seen_claim, seen_complete, seen_dropped, seen_id0, seen_out, seen_two;

    PlicClaim #(.N_SOURCES(N_SOURCES), .N_CONTEXTS(N_CONTEXTS)) u_plic_claim(
        .claim_en, .claim_id, .complete_en, .complete_id, .ie, .claim, .complete);

    task automatic check();
        logic [N_SOURCES:0] exp_claim;
        logic [N_SOURCES:0] exp_complete;
        int                 claims_of [N_SOURCES+1];
        exp_claim    = '0;
        exp_complete = '0;
        foreach (claims_of[k])
            claims_of[k] = 0;
        for (int c = 0; c < N_CONTEXTS; c++) begin
            int                 cl;
            int                 co;
            logic [N_SOURCES:0] row;    // ie[c]: Icarus does not take ie[c][co], both variable
            cl  = int'(claim_id[c]);
            co  = int'(complete_id[c]);
            row = ie[c];
            if (claim_en[c] && cl >= 1 && cl <= N_SOURCES) begin
                exp_claim[cl] = 1'b1;
                claims_of[cl]++;
            end
            if (complete_en[c] && co >= 1 && co <= N_SOURCES) begin
                if (row[co])
                    exp_complete[co] = 1'b1;
                else
                    seen_dropped = 1'b1;
            end
            if ((claim_en[c] && cl == 0) || (complete_en[c] && co == 0))
                seen_id0 = 1'b1;
            if ((claim_en[c] && cl > N_SOURCES) || (complete_en[c] && co > N_SOURCES))
                seen_out = 1'b1;
        end
        foreach (claims_of[k])
            if (claims_of[k] > 1)
                seen_two = 1'b1;
        #1;
        if (claim !== exp_claim || complete !== exp_complete)
            `DC_TEST_FAIL(model, $sformatf(
                "PlicClaim N=%0d C=%0d: claim %b complete %b, expected %b %b",
                N_SOURCES, N_CONTEXTS, claim, complete, exp_claim, exp_complete))
        if (exp_claim != '0)
            seen_claim = 1'b1;
        if (exp_complete != '0)
            seen_complete = 1'b1;
    endtask

    initial begin
        done = 1'b0;
        {seen_claim, seen_complete, seen_dropped, seen_id0, seen_out, seen_two} = '0;
        seed = N_SOURCES * 10 + N_CONTEXTS;
        {claim_en, claim_id, complete_en, complete_id} = '0;
        ie = '1;
        check();
        // Every context claims and completes the last source, then ID 0.
        claim_en    = '1;
        complete_en = '1;
        for (int c = 0; c < N_CONTEXTS; c++) begin
            claim_id[c]    = IDW'(N_SOURCES);
            complete_id[c] = IDW'(N_SOURCES);
        end
        check();
        claim_id    = '0;
        complete_id = '0;
        check();
        // A complete of a source not enabled for the context, then the highest ID.
        ie[0][1]       = 1'b0;
        complete_id[0] = IDW'(1);
        check();
        claim_id    = '1;
        complete_id = '1;
        check();
        for (int i = 0; i < N_RANDOM; i++) begin
            for (int c = 0; c < N_CONTEXTS; c++) begin
                claim_id[c]    = IDW'($random(seed));
                complete_id[c] = IDW'($random(seed));
                ie[c]          = (N_SOURCES + 1)'({$random(seed), $random(seed)});
            end
            claim_en    = N_CONTEXTS'($random(seed));
            complete_en = N_CONTEXTS'($random(seed));
            check();
        end
        if (!seen_claim || !seen_complete || !seen_dropped || !seen_id0 ||
            (OUT_RANGE && !seen_out) || (N_CONTEXTS > 1 && !seen_two))
            `DC_TEST_FAIL(cover, $sformatf(
                "PlicClaim N=%0d C=%0d: claim %b complete %b dropped %b id0 %b out %b two %b",
                N_SOURCES, N_CONTEXTS, seen_claim, seen_complete, seen_dropped, seen_id0,
                seen_out, seen_two))
        done = 1'b1;
    end
endmodule

module TbPlicClaim;
    `DC_TEST_MUTANT_HOOK(top)

    wire done_1_1, done_3_2, done_5_3, done_31_2, done_32_4;

    TbPlicClaimCheck #(.N_SOURCES(1),  .N_CONTEXTS(1)) u_check_1_1(.done(done_1_1));
    TbPlicClaimCheck #(.N_SOURCES(3),  .N_CONTEXTS(2)) u_check_3_2(.done(done_3_2));
    TbPlicClaimCheck #(.N_SOURCES(5),  .N_CONTEXTS(3)) u_check_5_3(.done(done_5_3));
    TbPlicClaimCheck #(.N_SOURCES(31), .N_CONTEXTS(2)) u_check_31_2(.done(done_31_2));
    TbPlicClaimCheck #(.N_SOURCES(32), .N_CONTEXTS(4)) u_check_32_4(.done(done_32_4));

    initial begin
        wait (done_1_1 && done_3_2 && done_5_3 && done_31_2 && done_32_4);
        $display("PASS");
        $finish;
    end
endmodule
