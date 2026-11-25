/* Test of NocSwitchAlloc.
 *
 * The input VCs' requests as the input units would make them (sa_req: valid while active with
 * a front flit, the route as its port, the output VC): a VC gets a packet now and then
 * (active, a route, an output VC) and keeps it while it has flits; its front flit is there in
 * most clocks; a pop takes a flit, after which the packet may end. Idle VCs come with random
 * fields and valid 0, or (combined allocation) hold a head that asks with need_vc: eligible
 * when its port has a free output VC with a credit; when it pops it must be given the highest
 * of them (vc_grant), and vc_alloc must name exactly the VCs given, at most one per output;
 * no grant otherwise. The output VCs are free or taken (taken when given, free again now and
 * then). Checked before every rising edge, by the rules of switch allocation rather than a
 * copy of the arbiters: a pop only from an eligible VC (active, a flit, a credit for its route
 * and output VC; a head: a free VC with a credit at its route); the inputs that pop and the
 * outputs that take a flit match one to one, each output taking an input whose popped VC
 * wants it; a flit goes whenever a VC is eligible. In the first half of the run the credits
 * are random; in the second every output VC has one and is free, so an eligible VC stays
 * eligible, and it must pop within (2 * NUM_VCS - 1) * N clocks: round robin at both stages,
 * the input's order moving only when its pick wins, so a pick waits at most N clocks at its
 * output; before our VC the input serves each other VC once, and a VC that becomes eligible
 * ahead of the pick takes the pick over (its wait at the output starts again), once per other
 * VC. Every case must happen: two inputs whose eligible VCs want one output, an input with two
 * eligible VCs (with more than one VC), a VC held back by its credit, flits to every output,
 * three or more flits in one clock, a head given a VC, a head held back with no free VC at its
 * port. NUM_VCS 1 (Mig6's: no input-side arbiter), 2 and 3; Verilator 20000 clocks, Icarus
 * 500. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "../block/noc/dark_circuit_noc.svh"

module TbNocSwitchAllocCheck #(
    parameter NUM_VCS = 2
)(
    input  wire  clk,
    output logic done
);
    localparam N          = NocPkg::MESH_PORTS;
    localparam R          = N * NUM_VCS;
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS);
    localparam PORT_WIDTH = `DC_NOC_PORT_WIDTH(N);
`ifdef VERILATOR
    localparam N_CLOCKS   = 20000;
`else
    localparam N_CLOCKS   = 500;
`endif

    typedef `DC_NOC_VC_VLD_T(VC_WIDTH)                  vc_vld_t;
    typedef `DC_NOC_SA_REQ_T(PORT_WIDTH, VC_WIDTH)      sa_req_t;

    localparam SW = $bits(sa_req_t);
    localparam OW = $bits(NocPkg::vc_out_state_t);

    logic                                           rst_n;
    sa_req_t               [N-1:0][NUM_VCS-1:0]     sa_req;
    NocPkg::vc_out_state_t [N-1:0][NUM_VCS-1:0]     out_vc_state;
    vc_vld_t               [N-1:0]                  pop;
    logic                  [N-1:0][PORT_WIDTH-1:0]  xbar_sel;
    logic                  [N-1:0]                  xbar_valid;
    vc_vld_t               [N-1:0][NUM_VCS-1:0]     vc_grant;
    logic                  [N-1:0][NUM_VCS-1:0]     vc_alloc;
    // The multi-dimensional ports as flat vectors, picked with +: (Icarus).
    logic [R*SW-1:0]         in_flat;
    logic [R*OW-1:0]         out_flat;
    wire  [N*PORT_WIDTH-1:0] sel_flat;
    wire  [R*$bits(vc_vld_t)-1:0] grant_flat;
    wire  [R-1:0]            alloc_flat;

    assign sa_req       = in_flat;
    assign out_vc_state = out_flat;
    assign sel_flat     = xbar_sel;
    assign grant_flat   = vc_grant;
    assign alloc_flat   = vc_alloc;

    NocSwitchAlloc #(.N(N), .NUM_VCS(NUM_VCS)) u_alloc(
        .clk, .rst_n, .sa_req, .out_vc_state, .pop, .xbar_sel, .xbar_valid, .vc_grant,
        .vc_alloc);

    // The input VCs (plain arrays; the ports are driven from them).
    logic   active  [N][NUM_VCS];       // holds a packet
    logic   flit    [N][NUM_VCS];       // a flit at the front
    logic   head    [N][NUM_VCS];       // when not active: a head asking with need_vc
    logic   otaken  [N][NUM_VCS];       // output VCs: taken (not free)
    integer route   [N][NUM_VCS];
    integer out_vc  [N][NUM_VCS];
    logic   credit  [N][NUM_VCS];       // output VCs
    logic   popped  [N][NUM_VCS];       // popped at the edge before
    integer waited  [N][NUM_VCS];       // clocks eligible since its last pop
    logic   all_credits;                // second half: every output VC has a credit
    integer seed;

    // Cases seen.
    integer n_out [N];                  // flits per output
    integer n_contend;                  // two inputs whose eligible VCs want one output
    integer n_two_vcs;                  // an input with two eligible VCs
    integer n_no_credit;                // an active VC with a flit held back by its credit
    integer n_three;                    // three or more flits in one clock
    integer n_head_go;                  // a head popped and given a VC
    integer n_head_blocked;             // a head with a flit, no free VC with a credit

    // The VC a head at output r gets: the highest free VC with a credit, -1 if none.
    // (r is an index: its high bits are 0.)
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic integer free_vc(input integer r);
        integer h;
        h = -1;
        for (int w = 0; w < NUM_VCS; w++)
            if (!otaken[r][w] && credit[r][w])
                h = w;
        return h;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // VC v of input p may send. (p and v are indexes: their high bits are 0.)
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic eligible(input integer p, input integer v);
        if (head[p][v])
            return flit[p][v] && free_vc(route[p][v]) >= 0;
        return active[p][v] && flit[p][v] && credit[route[p][v]][out_vc[p][v]];
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // After the edge: packets come, flits come and go, packets end, credits change.
    task automatic traffic;
        for (int p = 0; p < N; p++)
            for (int v = 0; v < NUM_VCS; v++) begin
                if (popped[p][v] && head[p][v]) begin   // a head went: more flits, or not
                    head[p][v]   = 1'b0;
                    active[p][v] = {$random(seed)} % 2 == 0;
                end else if (popped[p][v] && {$random(seed)} % 2 == 0)
                    active[p][v] = 1'b0;            // that was the tail
                if (!active[p][v] && !head[p][v] && {$random(seed)} % 4 == 0) begin
                    if ({$random(seed)} % 2 == 0) begin
                        active[p][v] = 1'b1;
                        out_vc[p][v] = {$random(seed)} % NUM_VCS;
                    end else
                        head[p][v] = 1'b1;          // asks the switch with need_vc
                    route[p][v]  = {$random(seed)} % N;
                    waited[p][v] = 0;
                end
                if (!active[p][v] && !head[p][v]) begin
                    route[p][v]  = {$random(seed)} % N;
                    out_vc[p][v] = {$random(seed)} % NUM_VCS;
                end
                if (all_credits || (otaken[p][v] && {$random(seed)} % 4 == 0))
                    otaken[p][v] = 1'b0;            // the packet holding it went
                flit[p][v]   = all_credits || {$random(seed)} % 10 < 8;
                credit[p][v] = all_credits || {$random(seed)} % 10 < 7;
                popped[p][v] = 1'b0;
            end
    endtask

    task automatic drive_ports;
        sa_req_t               s;
        NocPkg::vc_out_state_t o;
        for (int p = 0; p < N; p++)
            for (int v = 0; v < NUM_VCS; v++) begin
                s.valid   = (active[p][v] || head[p][v]) && flit[p][v];
                s.need_vc = head[p][v];
                s.port  = PORT_WIDTH'(route[p][v]);
                s.vc    = VC_WIDTH'(out_vc[p][v]);
                o.free       = !otaken[p][v];
                o.has_credit = credit[p][v];
                in_flat[(p * NUM_VCS + v) * SW +: SW]  = s;
                out_flat[(p * NUM_VCS + v) * OW +: OW] = o;
            end
    endtask

    // Before the edge: the rules; then the pops are noted for the next clock.
    task automatic check;
        vc_vld_t g;
        integer  sel;
        logic    taken [N];             // per input: an output took it
        integer  wants [N];             // per output: inputs with an eligible VC that wants it
        integer  any;                   // eligible VCs
        integer  flits;
        integer  e;
        for (int p = 0; p < N; p++) begin
            taken[p] = 1'b0;
            wants[p] = 0;
        end
        any = 0;
        for (int p = 0; p < N; p++) begin
            e = 0;
            for (int v = 0; v < NUM_VCS; v++)
                if (eligible(p, v)) begin
                    e = e + 1;
                    any = any + 1;
                end else if (active[p][v] && flit[p][v])
                    n_no_credit = n_no_credit + 1;
            if (e > 1) n_two_vcs = n_two_vcs + 1;
            for (int r = 0; r < N; r++) begin
                e = 0;
                for (int v = 0; v < NUM_VCS; v++)
                    if (eligible(p, v) && route[p][v] == r) e = 1;
                wants[r] = wants[r] + e;
            end
        end
        for (int r = 0; r < N; r++)
            if (wants[r] > 1) n_contend = n_contend + 1;
        // Each output that takes a flit: an input that pops a VC wanting this output.
        flits = 0;
        for (int r = 0; r < N; r++)
            if (xbar_valid[r]) begin
                sel = int'(sel_flat[r * PORT_WIDTH +: PORT_WIDTH]);
                g   = pop[sel];
                if (sel >= N || !g.valid || taken[sel] || route[sel][g.vc] != r)
                    $fatal(1, "NocSwitchAlloc %0d: output %0d takes input %0d (pop %b VC %0d)",
                           NUM_VCS, r, sel, g.valid, g.vc);
                taken[sel] = 1'b1;
                flits      = flits + 1;
                n_out[r]   = n_out[r] + 1;
            end
        // Each pop: an eligible VC, taken by an output.
        for (int p = 0; p < N; p++) begin
            g = pop[p];
            if (g.valid && (int'(g.vc) >= NUM_VCS || !eligible(p, int'(g.vc))))
                $fatal(1, "NocSwitchAlloc %0d: input %0d pops VC %0d, not eligible", NUM_VCS, p,
                       g.vc);
            if (g.valid != taken[p])
                $fatal(1, "NocSwitchAlloc %0d: input %0d pops %b, taken by an output %b", NUM_VCS,
                       p, g.valid, taken[p]);
        end
        check_vcs();
        if (any > 0 && flits == 0)
            $fatal(1, "NocSwitchAlloc %0d: %0d eligible VCs, no flit goes", NUM_VCS, any);
        if (flits >= 3) n_three = n_three + 1;
        // Fairness (every output VC with a credit): an eligible VC pops within
        // (2 * NUM_VCS - 1) * N clocks (see the header).
        for (int p = 0; p < N; p++)
            for (int v = 0; v < NUM_VCS; v++) begin
                g = pop[p];
                if (g.valid && int'(g.vc) == v) begin
                    popped[p][v] = 1'b1;
                    waited[p][v] = 0;
                end else if (all_credits && eligible(p, v)) begin
                    waited[p][v] = waited[p][v] + 1;
                    if (waited[p][v] > (2 * NUM_VCS - 1) * N)
                        $fatal(1, "NocSwitchAlloc %0d: VC %0d of input %0d eligible %0d clocks",
                               NUM_VCS, v, p, waited[p][v]);
                end
            end
    endtask

    // The VCs given: a head that pops gets its port's free VC; vc_alloc names exactly those;
    // nothing else is granted. Then the model takes the VCs given.
    task automatic check_vcs;
        vc_vld_t g;
        vc_vld_t vg;
        integer  fv;
        logic    gives [N][NUM_VCS];    // the output VCs given this clock, by the rules
        for (int r = 0; r < N; r++)
            for (int w = 0; w < NUM_VCS; w++)
                gives[r][w] = 1'b0;
        for (int p = 0; p < N; p++) begin
            g = pop[p];
            for (int v = 0; v < NUM_VCS; v++) begin
                vg = grant_flat[(p * NUM_VCS + v) * $bits(vc_vld_t) +: $bits(vc_vld_t)];
                if (head[p][v] && flit[p][v] && free_vc(route[p][v]) < 0)
                    n_head_blocked = n_head_blocked + 1;
                if (g.valid && int'(g.vc) == v && head[p][v]) begin
                    fv = free_vc(route[p][v]);
                    if (!vg.valid || int'(vg.vc) != fv)
                        $fatal(1, "NocSwitchAlloc %0d: head %0d/%0d: grant %b %0d, expected %0d",
                               NUM_VCS, p, v, vg.valid, vg.vc, fv);
                    gives[route[p][v]][fv] = 1'b1;
                    n_head_go = n_head_go + 1;
                end else if (vg.valid)
                    $fatal(1, "NocSwitchAlloc %0d: VC %0d/%0d granted, not a head that pops",
                           NUM_VCS, p, v);
            end
        end
        for (int r = 0; r < N; r++)
            for (int w = 0; w < NUM_VCS; w++) begin
                if (alloc_flat[r * NUM_VCS + w] !== gives[r][w])
                    $fatal(1, "NocSwitchAlloc %0d: output %0d VC %0d alloc %b, expected %b",
                           NUM_VCS, r, w, alloc_flat[r * NUM_VCS + w], gives[r][w]);
                if (gives[r][w])
                    otaken[r][w] = 1'b1;
            end
    endtask

    initial begin
        done        = 1'b0;
        seed        = NUM_VCS * 19;
        all_credits = 1'b0;
        n_contend   = 0;
        n_two_vcs   = 0;
        n_no_credit = 0;
        n_three     = 0;
        n_head_go      = 0;
        n_head_blocked = 0;
        for (int p = 0; p < N; p++) begin
            n_out[p] = 0;
            for (int v = 0; v < NUM_VCS; v++) begin
                active[p][v] = 1'b0;
                head[p][v]   = 1'b0;
                otaken[p][v] = 1'b0;
                flit[p][v]   = 1'b0;
                route[p][v]  = 0;
                out_vc[p][v] = 0;
                credit[p][v] = 1'b0;
                popped[p][v] = 1'b0;
                waited[p][v] = 0;
            end
        end
        rst_n = 1'b0;
        drive_ports();
        @(negedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        for (int k = 0; k < N_CLOCKS; k++) begin
            all_credits = k >= N_CLOCKS / 2;
            traffic();
            drive_ports();
            #1;
            check();
            @(negedge clk);
        end
        for (int r = 0; r < N; r++)
            if (n_out[r] == 0)
                $fatal(1, "NocSwitchAlloc %0d: no flit to output %0d", NUM_VCS, r);
        if (n_contend == 0 || (NUM_VCS > 1 && n_two_vcs == 0) || n_no_credit == 0 ||
            n_three == 0 || n_head_go == 0 || n_head_blocked == 0)
            $fatal(1, "NocSwitchAlloc %0d: cases %0d %0d %0d %0d, heads %0d %0d", NUM_VCS,
                   n_contend, n_two_vcs, n_no_credit, n_three, n_head_go, n_head_blocked);
        done = 1'b1;
    end
endmodule

module TbNocSwitchAlloc;
    wire clk;
    wire done_2;
    wire done_3;
    wire done_1;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbNocSwitchAllocCheck #(.NUM_VCS(1)) u_check_1(.clk, .done(done_1));
    TbNocSwitchAllocCheck #(.NUM_VCS(2)) u_check_2(.clk, .done(done_2));
    TbNocSwitchAllocCheck #(.NUM_VCS(3)) u_check_3(.clk, .done(done_3));

    initial begin
        wait (done_1 && done_2 && done_3);
        $display("PASS");
        $finish;
    end
endmodule
