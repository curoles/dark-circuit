/* Test of NocVirtChRtrInputUnit.
 *
 * The input port of the router at (1, 2) of a 4 x 4 mesh. An upstream sender keeps a credit
 * count per VC and sends a flit of a VC that has a credit in most clocks, the VCs in random
 * order, so the flits of packets of different VCs interleave (packets of 1 to 4 flits to random
 * destinations); a credit coming back on the link returns one. VC allocation grants a waiting
 * VC a random output VC in half of the clocks; switch allocation pops one active VC with a flit
 * in most clocks. A model keeps every VC's flits, state, route (XY, computed here from the
 * head's destination) and output VC; every clock each VC's state, the flit to the crossbar
 * (with the output VC in its vc field) and the credit on the link (the pop of the clock before)
 * must be the model's. Every case must happen: every VC used, a flit of one VC between flits of
 * a packet of another, routes to all five ports, two pops in a row. NUM_VCS 2 and 3 (vc values
 * that name no VC); Verilator 20000 clocks, Icarus 2000. Stops at the first mismatch with
 * $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "../block/noc/dark_circuit_noc.svh"

module TbNocVirtChRtrInputUnitCheck #(
    parameter NUM_VCS = 2
)(
    input  wire  clk,
    output logic done
);
    localparam BUF_DEPTH  = 2;
    localparam X_WIDTH    = 2;
    localparam Y_WIDTH    = 2;
    localparam DATA_WIDTH = 16;
    localparam MY_X       = 1;
    localparam MY_Y       = 2;
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS);
    localparam PORT_WIDTH = `DC_NOC_PORT_WIDTH(NocPkg::MESH_PORTS);
    localparam REST_WIDTH = DATA_WIDTH - X_WIDTH - Y_WIDTH;    // a head's data after the route
`ifdef VERILATOR
    localparam N_CLOCKS   = 20000;
`else
    localparam N_CLOCKS   = 2000;
`endif

    typedef `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH)            flit_t;
    typedef `DC_NOC_HEAD_T(X_WIDTH, Y_WIDTH, DATA_WIDTH)    head_t;
    typedef `DC_NOC_FLIT_VLD_T(VC_WIDTH, DATA_WIDTH)        flit_vld_t;
    typedef `DC_NOC_VC_VLD_T(VC_WIDTH)                      vc_vld_t;
    typedef `DC_NOC_VC_IN_STATE_T(PORT_WIDTH, VC_WIDTH)     vc_state_t;

    logic                     rst_n;
    flit_vld_t                in_fwd;
    vc_vld_t                  in_bwd;
    vc_state_t [NUM_VCS-1:0]  vc_state;
    vc_vld_t   [NUM_VCS-1:0]  vc_grant;
    vc_vld_t                  pop;
    flit_vld_t                out;

    NocVirtChRtrInputUnit #(.NUM_VCS(NUM_VCS), .BUF_DEPTH(BUF_DEPTH), .X_WIDTH(X_WIDTH),
                            .Y_WIDTH(Y_WIDTH), .DATA_WIDTH(DATA_WIDTH), .MY_X(MY_X),
                            .MY_Y(MY_Y)) u_input_unit(
        .clk, .rst_n, .in_fwd, .in_bwd, .vc_state, .vc_grant, .pop, .out);

    // XY route of a head flit seen from (MY_X, MY_Y), written as the cases of the mesh (only the
    // destination of the flit is used).
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic integer xy_port(input flit_t f);
        head_t h;
        h = f.data;
        if (int'(h.dest_x) > MY_X) return NocPkg::PORT_EAST;
        if (int'(h.dest_x) < MY_X) return NocPkg::PORT_WEST;
        if (int'(h.dest_y) > MY_Y) return NocPkg::PORT_NORTH;
        if (int'(h.dest_y) < MY_Y) return NocPkg::PORT_SOUTH;
        return NocPkg::PORT_LOCAL;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic flit_t with_vc(input flit_t f, input logic [VC_WIDTH-1:0] vc);
        flit_t g;
        g    = f;
        g.vc = vc;
        return g;
    endfunction

    // Model, per VC: flits in the buffer (fixed arrays: Icarus has no queues of structs), state.
    flit_t                 m_buf    [NUM_VCS][BUF_DEPTH];
    integer                m_count  [NUM_VCS];
    logic [1:0]            m_state  [NUM_VCS];
    logic [PORT_WIDTH-1:0] m_route  [NUM_VCS];
    logic [VC_WIDTH-1:0]   m_out_vc [NUM_VCS];
    // The sender, per VC: credits, flits left of the packet being sent.
    integer                credits  [NUM_VCS];
    integer                left     [NUM_VCS];
    vc_vld_t               pop_before;  // the pop of the clock before: its credit is due now
    logic                  popped_before;
    integer                seed;

    // Cases seen.
    integer n_vc_used [NUM_VCS];
    integer n_port    [NocPkg::MESH_PORTS];
    integer n_interleave;       // a flit of one VC while a packet of another is half sent
    integer n_pop_pop;          // two pops in a row

    // The next flit the sender has for VC v: a new packet's head when the last one ended. (v is
    // an index below NUM_VCS: its high bits are 0.)
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic flit_t next_flit(input integer v);
        flit_t f;
        head_t h;
        integer len;
        f    = '0;
        f.vc = VC_WIDTH'(v);
        if (left[v] == 0) begin
            len      = 1 + {$random(seed)} % 4;
            left[v]  = len;
            f.head   = 1'b1;
            h        = '0;
            h.dest_x = X_WIDTH'($random(seed));
            h.dest_y = Y_WIDTH'($random(seed));
            h.rest   = REST_WIDTH'($random(seed));
            f.data   = h;
        end else
            f.data = DATA_WIDTH'($random(seed));
        f.tail = (left[v] == 1);
        return f;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // Inputs of this clock, after the rising edge. Elements of the packed arrays are written
    // whole (Icarus: no field of an element picked by a variable index).
    task automatic drive;
        integer  v;
        logic    half_sent;     // another VC has a packet half sent
        vc_vld_t g;
        in_fwd   = '0;
        vc_grant = '0;
        pop      = '0;
        // The sender: a random VC with a credit.
        v = {$random(seed)} % NUM_VCS;
        if (credits[v] > 0 && {$random(seed)} % 10 < 8) begin
            half_sent = 1'b0;
            for (int w = 0; w < NUM_VCS; w++)
                if (w != v && left[w] != 0)
                    half_sent = 1'b1;
            in_fwd.valid = 1'b1;
            in_fwd.flit  = next_flit(v);
            n_vc_used[v] = n_vc_used[v] + 1;
            if (half_sent) n_interleave = n_interleave + 1;
        end
        // VC allocation: each waiting VC in half of the clocks.
        for (int w = 0; w < NUM_VCS; w++)
            if (m_state[w] == NocPkg::VC_WAIT_VC && {$random(seed)} % 2 == 0) begin
                g.valid     = 1'b1;
                g.vc        = VC_WIDTH'($random(seed));
                vc_grant[w] = g;
            end
        // Switch allocation: one active VC with a flit, a random one.
        v = {$random(seed)} % NUM_VCS;
        for (int k = 0; k < NUM_VCS; k++) begin
            if (!pop.valid && m_state[(v + k) % NUM_VCS] == NocPkg::VC_ACTIVE &&
                m_count[(v + k) % NUM_VCS] > 0 && {$random(seed)} % 10 < 8) begin
                pop.valid = 1'b1;
                pop.vc    = VC_WIDTH'((v + k) % NUM_VCS);
            end
        end
    endtask

    // Outputs of this clock: those of the model (an element read whole, then its fields).
    task automatic check;
        vc_state_t s;
        for (int v = 0; v < NUM_VCS; v++) begin
            s = vc_state[v];
            if (s.state !== m_state[v] || s.has_flit !== (m_count[v] > 0) ||
                (m_state[v] != NocPkg::VC_IDLE && s.route !== m_route[v]) ||
                (m_state[v] == NocPkg::VC_ACTIVE && s.out_vc !== m_out_vc[v]))
                $fatal(1, "InputUnit %0d: VC %0d state %0d flit %b route %0d vc %0d, expected %0d %b %0d %0d",
                       NUM_VCS, v, s.state, s.has_flit, s.route, s.out_vc, m_state[v],
                       m_count[v] > 0, m_route[v], m_out_vc[v]);
        end
        if (out.valid !== pop.valid ||
            (pop.valid && out.flit !== with_vc(m_buf[pop.vc][0], m_out_vc[pop.vc])))
            $fatal(1, "InputUnit %0d: out %b %h, expected %b %h", NUM_VCS, out.valid, out.flit,
                   pop.valid, with_vc(m_buf[pop.vc][0], m_out_vc[pop.vc]));
        if (in_bwd.valid !== pop_before.valid || (in_bwd.valid && in_bwd.vc !== pop_before.vc))
            $fatal(1, "InputUnit %0d: credit %b %0d, expected %b %0d", NUM_VCS, in_bwd.valid,
                   in_bwd.vc, pop_before.valid, pop_before.vc);
    endtask

    // Model of the rising edge. Array elements are read whole into f0 and g first (Icarus:
    // no field of an element of an array of structs picked by a variable index).
    task automatic model_edge;
        // An index below NUM_VCS: its high bits are 0.
        /* verilator lint_off UNUSEDSIGNAL */
        integer  v;
        /* verilator lint_on UNUSEDSIGNAL */
        flit_t   f0;            // the front flit of a VC
        vc_vld_t g;             // the grant of a VC
        // The state of each VC moves with its front flit of this clock.
        for (int w = 0; w < NUM_VCS; w++) begin
            f0 = m_buf[w][0];
            g  = vc_grant[w];
            case (m_state[w])
                NocPkg::VC_IDLE:
                    if (m_count[w] > 0 && f0.head) begin
                        m_state[w] = NocPkg::VC_WAIT_VC;
                        m_route[w] = PORT_WIDTH'(xy_port(f0));
                        n_port[xy_port(f0)] = n_port[xy_port(f0)] + 1;
                    end
                NocPkg::VC_WAIT_VC:
                    if (g.valid) begin
                        m_state[w]  = NocPkg::VC_ACTIVE;
                        m_out_vc[w] = g.vc;
                    end
                default:
                    if (pop.valid && int'(pop.vc) == w && f0.tail)
                        m_state[w] = NocPkg::VC_IDLE;
            endcase
        end
        // The pop leaves its VC; the link's flit goes into its VC; the credit due comes back.
        if (pop.valid) begin
            v = int'(pop.vc);
            for (int i = 0; i + 1 < BUF_DEPTH; i++)
                m_buf[v][i] = m_buf[v][i + 1];
            m_count[v] = m_count[v] - 1;
            if (popped_before) n_pop_pop = n_pop_pop + 1;
        end
        if (in_fwd.valid) begin
            v = int'(in_fwd.flit.vc);
            m_buf[v][m_count[v]] = in_fwd.flit;
            m_count[v]           = m_count[v] + 1;
            credits[v]           = credits[v] - 1;
            left[v]              = left[v] - 1;
        end
        if (pop_before.valid)
            credits[int'(pop_before.vc)] = credits[int'(pop_before.vc)] + 1;
        popped_before = pop.valid;
        pop_before    = pop;
    endtask

    initial begin
        done          = 1'b0;
        seed          = NUM_VCS * 13;
        for (int v = 0; v < NUM_VCS; v++) begin
            m_count[v]   = 0;
            m_state[v]   = NocPkg::VC_IDLE;
            m_route[v]   = '0;
            m_out_vc[v]  = '0;
            credits[v]   = BUF_DEPTH;
            left[v]      = 0;
            n_vc_used[v] = 0;
        end
        for (int p = 0; p < NocPkg::MESH_PORTS; p++)
            n_port[p] = 0;
        n_interleave  = 0;
        n_pop_pop     = 0;
        pop_before    = '0;
        popped_before = 1'b0;
        rst_n         = 1'b0;
        in_fwd        = '0;
        vc_grant      = '0;
        pop           = '0;
        @(negedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        for (int k = 0; k < N_CLOCKS; k++) begin
            drive();
            #1;
            check();
            model_edge();
            @(negedge clk);
        end
        for (int v = 0; v < NUM_VCS; v++)
            if (n_vc_used[v] == 0)
                $fatal(1, "InputUnit %0d: VC %0d never used", NUM_VCS, v);
        for (int p = 0; p < NocPkg::MESH_PORTS; p++)
            if (n_port[p] == 0)
                $fatal(1, "InputUnit %0d: no route to port %0d", NUM_VCS, p);
        if (n_interleave == 0 || n_pop_pop == 0)
            $fatal(1, "InputUnit %0d: cases: interleave %0d, pop after pop %0d", NUM_VCS,
                   n_interleave, n_pop_pop);
        done = 1'b1;
    end
endmodule

module TbNocVirtChRtrInputUnit;
    wire clk;
    wire done_2;
    wire done_3;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbNocVirtChRtrInputUnitCheck #(.NUM_VCS(2)) u_check_2(.clk, .done(done_2));
    TbNocVirtChRtrInputUnitCheck #(.NUM_VCS(3)) u_check_3(.clk, .done(done_3));

    initial begin
        wait (done_2 && done_3);
        $display("PASS");
        $finish;
    end
endmodule
