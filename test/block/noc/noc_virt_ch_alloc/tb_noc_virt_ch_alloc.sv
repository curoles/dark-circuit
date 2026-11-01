/* Test of NocVirtChAlloc.
 *
 * The input VCs and the output VCs around the allocator, as the router's units would be: an
 * idle input VC gets a head with a random route now and then and waits; a grant makes it active
 * and its output VC taken at the edge (as NocVirtChIn and NocVirtChOut take them); an active
 * input VC goes idle now and then, a taken output VC free (its tail left). Checked before every
 * rising edge, against the rules of VC allocation rather than a copy of the arbiter: a grant
 * only to a waiting input VC, at the port of its route, with a free VC of that port; at most one
 * grant per port; vc_alloc names exactly the VCs granted; a port that has a waiting input VC and
 * a free VC grants (work-conserving); an input VC that waits is granted within N * NUM_VCS - 1
 * grants of its port to others (round robin). Every case must happen: grants at every port, two
 * grants in one clock, two input VCs waiting for one port, a port with waiting input VCs and no
 * free VC. NUM_VCS 2 and 3; Verilator 20000 clocks, Icarus 2000. Stops at the first mismatch
 * with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "../block/noc/dark_circuit_noc.svh"

module TbNocVirtChAllocCheck #(
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
    localparam N_CLOCKS   = 2000;
`endif

    typedef `DC_NOC_VC_VLD_T(VC_WIDTH)                  vc_vld_t;
    typedef `DC_NOC_VC_IN_STATE_T(PORT_WIDTH, VC_WIDTH) vc_state_t;

    localparam SW = $bits(vc_state_t);              // bits of an element of each port
    localparam OW = $bits(NocPkg::vc_out_state_t);
    localparam GW = $bits(vc_vld_t);

    logic                                        rst_n;
    vc_state_t             [N-1:0][NUM_VCS-1:0]  in_vc_state;
    NocPkg::vc_out_state_t [N-1:0][NUM_VCS-1:0]  out_vc_state;
    vc_vld_t               [N-1:0][NUM_VCS-1:0]  vc_grant;
    logic                  [N-1:0][NUM_VCS-1:0]  vc_alloc;
    // The ports as flat vectors, element (p, v) at (p * NUM_VCS + v) * its bits, picked with +:
    // (Icarus: no variable index into a multi-dimensional packed array).
    logic [R*SW-1:0] in_flat;
    logic [R*OW-1:0] out_flat;
    wire  [R*GW-1:0] grant_flat;
    wire  [R-1:0]    alloc_flat;

    assign in_vc_state  = in_flat;
    assign out_vc_state = out_flat;
    assign grant_flat   = vc_grant;
    assign alloc_flat   = vc_alloc;

    NocVirtChAlloc #(.N(N), .NUM_VCS(NUM_VCS)) u_alloc(
        .clk, .rst_n, .in_vc_state, .out_vc_state, .vc_grant, .vc_alloc);

    // The units around the allocator (plain arrays; the ports are driven from them).
    logic [1:0] in_state [N][NUM_VCS];
    integer     in_route [N][NUM_VCS];
    integer     others   [N][NUM_VCS];  // grants of its port to others while it waits
    logic       taken    [N][NUM_VCS];  // output VCs
    integer     seed;

    // Cases seen.
    integer n_port [N];                 // grants per port
    integer n_two;                      // two grants in one clock
    integer n_contend;                  // two input VCs waiting for one port
    integer n_blocked;                  // a port with waiting input VCs and no free VC

    // The ports from the arrays.
    task automatic drive_ports;
        vc_state_t             s;
        NocPkg::vc_out_state_t o;
        for (int p = 0; p < N; p++)
            for (int v = 0; v < NUM_VCS; v++) begin
                s       = '0;
                s.state = in_state[p][v];
                s.route = PORT_WIDTH'(in_route[p][v]);
                o.free       = !taken[p][v];
                o.has_credit = 1'b1;
                in_flat[(p * NUM_VCS + v) * SW +: SW]  = s;
                out_flat[(p * NUM_VCS + v) * OW +: OW] = o;
            end
    endtask

    // Before the rising edge: the grants by the rules; then the edge.
    task automatic check_and_edge;
        vc_vld_t g;
        integer  grants_at [N];         // grants per port this clock
        integer  waiting   [N];         // input VCs waiting per port
        logic    has_free  [N];
        integer  allocs;                // VCs of a port in vc_alloc
        integer  total;
        for (int r = 0; r < N; r++) begin
            grants_at[r] = 0;
            waiting[r]   = 0;
            has_free[r]  = 1'b0;
            for (int w = 0; w < NUM_VCS; w++)
                if (!taken[r][w]) has_free[r] = 1'b1;
        end
        for (int p = 0; p < N; p++)
            for (int v = 0; v < NUM_VCS; v++)
                if (in_state[p][v] == NocPkg::VC_WAIT_VC)
                    waiting[in_route[p][v]] = waiting[in_route[p][v]] + 1;
        // Every grant: to a waiting input VC, a free VC of its route's port, named by vc_alloc.
        for (int p = 0; p < N; p++)
            for (int v = 0; v < NUM_VCS; v++) begin
                g = grant_flat[(p * NUM_VCS + v) * GW +: GW];
                if (g.valid) begin
                    if (in_state[p][v] != NocPkg::VC_WAIT_VC)
                        $fatal(1, "NocVirtChAlloc %0d: grant to input VC %0d.%0d, not waiting",
                               NUM_VCS, p, v);
                    if (int'(g.vc) >= NUM_VCS || taken[in_route[p][v]][g.vc])
                        $fatal(1, "NocVirtChAlloc %0d: input VC %0d.%0d got VC %0d of port %0d, not free",
                               NUM_VCS, p, v, g.vc, in_route[p][v]);
                    if (!alloc_flat[in_route[p][v] * NUM_VCS + int'(g.vc)])
                        $fatal(1, "NocVirtChAlloc %0d: VC %0d of port %0d given, not in vc_alloc",
                               NUM_VCS, g.vc, in_route[p][v]);
                    if (others[p][v] > R - 1)
                        $fatal(1, "NocVirtChAlloc %0d: input VC %0d.%0d waited %0d grants",
                               NUM_VCS, p, v, others[p][v]);
                    grants_at[in_route[p][v]] = grants_at[in_route[p][v]] + 1;
                end
            end
        // Per port: at most one grant, vc_alloc only with it, work-conserving. (The VCs taken
        // are counted with a loop: Icarus counts $countones of a variable part-select wrong.)
        total = 0;
        for (int r = 0; r < N; r++) begin
            allocs = 0;
            for (int w = 0; w < NUM_VCS; w++)
                if (alloc_flat[r * NUM_VCS + w]) allocs = allocs + 1;
            if (grants_at[r] > 1 || allocs != grants_at[r])
                $fatal(1, "NocVirtChAlloc %0d: port %0d: %0d grants, %0d VCs taken", NUM_VCS, r,
                       grants_at[r], allocs);
            if (waiting[r] > 0 && has_free[r] && grants_at[r] == 0)
                $fatal(1, "NocVirtChAlloc %0d: port %0d has a waiting input VC and a free VC, no grant",
                       NUM_VCS, r);
            if (grants_at[r] > 0) n_port[r] = n_port[r] + 1;
            if (waiting[r] > 1)   n_contend = n_contend + 1;
            if (waiting[r] > 0 && !has_free[r]) n_blocked = n_blocked + 1;
            total = total + grants_at[r];
        end
        if (total > 1) n_two = n_two + 1;
        // The edge: the waiting input VCs count the grants of their port to others; a grant
        // makes its input VC active and its output VC taken.
        for (int p = 0; p < N; p++)
            for (int v = 0; v < NUM_VCS; v++) begin
                g = grant_flat[(p * NUM_VCS + v) * GW +: GW];
                if (in_state[p][v] == NocPkg::VC_WAIT_VC && !g.valid)
                    others[p][v] = others[p][v] + grants_at[in_route[p][v]];
            end
        for (int p = 0; p < N; p++)
            for (int v = 0; v < NUM_VCS; v++) begin
                g = grant_flat[(p * NUM_VCS + v) * GW +: GW];
                if (g.valid) begin
                    in_state[p][v]             = NocPkg::VC_ACTIVE;
                    taken[in_route[p][v]][g.vc] = 1'b1;
                end
            end
    endtask

    // After the edge: packets end, heads come, tails free output VCs.
    task automatic traffic;
        for (int p = 0; p < N; p++)
            for (int v = 0; v < NUM_VCS; v++) begin
                if (in_state[p][v] == NocPkg::VC_ACTIVE && {$random(seed)} % 4 == 0)
                    in_state[p][v] = NocPkg::VC_IDLE;
                else if (in_state[p][v] == NocPkg::VC_IDLE && {$random(seed)} % 3 == 0) begin
                    in_state[p][v] = NocPkg::VC_WAIT_VC;
                    in_route[p][v] = {$random(seed)} % N;
                    others[p][v]   = 0;
                end
                if (taken[p][v] && {$random(seed)} % 5 == 0)
                    taken[p][v] = 1'b0;
            end
    endtask

    initial begin
        done      = 1'b0;
        seed      = NUM_VCS * 17;
        n_two     = 0;
        n_contend = 0;
        n_blocked = 0;
        for (int p = 0; p < N; p++) begin
            n_port[p] = 0;
            for (int v = 0; v < NUM_VCS; v++) begin
                in_state[p][v] = NocPkg::VC_IDLE;
                in_route[p][v] = 0;
                others[p][v]   = 0;
                taken[p][v]    = 1'b0;
            end
        end
        rst_n = 1'b0;
        drive_ports();
        @(negedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        for (int k = 0; k < N_CLOCKS; k++) begin
            traffic();
            drive_ports();
            #1;
            check_and_edge();
            @(negedge clk);
        end
        for (int r = 0; r < N; r++)
            if (n_port[r] == 0)
                $fatal(1, "NocVirtChAlloc %0d: no grant at port %0d", NUM_VCS, r);
        if (n_two == 0 || n_contend == 0 || n_blocked == 0)
            $fatal(1, "NocVirtChAlloc %0d: cases: two grants %0d, contention %0d, blocked %0d",
                   NUM_VCS, n_two, n_contend, n_blocked);
        done = 1'b1;
    end
endmodule

module TbNocVirtChAlloc;
    wire clk;
    wire done_2;
    wire done_3;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbNocVirtChAllocCheck #(.NUM_VCS(2)) u_check_2(.clk, .done(done_2));
    TbNocVirtChAllocCheck #(.NUM_VCS(3)) u_check_3(.clk, .done(done_3));

    initial begin
        wait (done_2 && done_3);
        $display("PASS");
        $finish;
    end
endmodule
