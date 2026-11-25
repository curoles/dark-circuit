/* VC allocation of the NoC router, behavioral: a packet's head gets an output VC.
 *
 * Requesters are the input VCs' requests (va_req, NocVirtChIn's: a head waiting for an output
 * VC), each for one output port, its route: XY routing is deterministic, so an input VC asks one
 * port and can win at one port
 * only, and an arbiter per output port is the whole allocator (no input-side arbitration). Each
 * port with a free output VC grants one waiting input VC per clock (RoundRobinArbiter over all
 * input VCs) and gives it a free VC, the highest; a second head for the same port waits a clock.
 * It is a selection, not a general matching: valid for deterministic routing with any free VC
 * of the port allowed (NocVirtChRouter's assumption); adaptive routing or restricted VC sets
 * need a general allocator.
 * The grant goes to the input VC (vc_grant: valid, the output VC) and to the output VC
 * (vc_alloc); both take it at the next edge (NocVirtChIn becomes active, NocVirtChOut taken),
 * so an output VC is never given twice. The requests are made from the input VCs' flops; the
 * allocator knows nothing of their states, so a variant of the input VC that asks earlier needs
 * no change here.
 *
 *   va_req[p][v] -- valid, port == r ---------> req[r][p*NUM_VCS+v] --+
 *                                                                      v
 *   out_vc_state[r][w] -- free --> a free VC? --> RoundRobinArbiter [r] --> winner (p, v)
 *                                  the highest free: w                       |
 *                                        |                                   v
 *                                        +--> vc_alloc[r][w]   vc_grant[p][v] = {valid, w}
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"
`include "../block/noc/dark_circuit_noc.svh"

module NocVirtChAlloc #(
    parameter  N          = NocPkg::MESH_PORTS, // ports: inputs and outputs
    parameter  NUM_VCS    = 2,                  // virtual channels on every link
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS),
    localparam PORT_WIDTH = `DC_NOC_PORT_WIDTH(N),
    localparam type VC_VLD_T   = `DC_NOC_VC_VLD_T(VC_WIDTH),
    localparam type VA_REQ_T   = `DC_NOC_VA_REQ_T(PORT_WIDTH)
)(
    input  wire                                        clk,
    input  wire                                        rst_n,         // synchronous, active low
    input  VA_REQ_T               [N-1:0][NUM_VCS-1:0] va_req,        // input VCs: a VC of a port
    input  NocPkg::vc_out_state_t [N-1:0][NUM_VCS-1:0] out_vc_state,  // free output VCs
    output VC_VLD_T               [N-1:0][NUM_VCS-1:0] vc_grant,      // to an input VC: its VC
    output logic                  [N-1:0][NUM_VCS-1:0] vc_alloc       // an output VC taken
);
    localparam R = N * NUM_VCS;                 // requesters: every input VC, p * NUM_VCS + v

    logic [N-1:0][R-1:0]        req;            // per output port: the input VCs waiting for it
    logic [N-1:0][R-1:0]        win;            // per output port: one-hot, its winner
    logic [N-1:0][VC_WIDTH-1:0] free_vc;        // per output port: the free VC it gives

    // The highest set bit of the free VCs of a port.
    function automatic logic [VC_WIDTH-1:0] highest(input logic [NUM_VCS-1:0] free);
        logic [VC_WIDTH-1:0] h;
        h = '0;
        for (int w = 0; w < NUM_VCS; w++)
            if (free[w])
                h = VC_WIDTH'(w);
        return h;
    endfunction

    for (genvar p = 0; p < N; p++) begin: g_in_port
        for (genvar v = 0; v < NUM_VCS; v++) begin: g_in_vc
            VA_REQ_T      q;                    // the input VC's request
            logic [N-1:0] won;                  // per output port: this input VC won there
            VC_VLD_T      g;

            assign q = va_req[p][v];
            for (genvar r = 0; r < N; r++) begin: g_out_port
                assign req[r][p * NUM_VCS + v] = q.valid && q.port == PORT_WIDTH'(r);
                assign won[r] = win[r][p * NUM_VCS + v];
            end

            // It asked one port: the VC is that port's free VC.
            assign g.valid        = |won;
            assign g.vc           = free_vc[q.port];
            assign vc_grant[p][v] = g;

            `DC_ASSERT(a_wins_one_port, $onehot0(won))
        end
    end

    for (genvar r = 0; r < N; r++) begin: g_out_port
        logic [NUM_VCS-1:0] free;               // the free output VCs of this port

        for (genvar w = 0; w < NUM_VCS; w++) begin: g_out_vc
            // The output VC's state: only free is read here (credits: switch allocation).
            /* verilator lint_off UNUSEDSIGNAL */
            NocPkg::vc_out_state_t o;
            /* verilator lint_on UNUSEDSIGNAL */

            assign o              = out_vc_state[r][w];
            assign free[w]        = o.free;
            assign vc_alloc[r][w] = |win[r] && free_vc[r] == VC_WIDTH'(w);
        end
        assign free_vc[r] = highest(free);

        // Only a port with a free VC grants; its grant is always used.
        RoundRobinArbiter #(.N(R)) u_arbiter(
            .clk, .rst_n, .req(req[r] & {R{|free}}), .advance(1'b1), .grant(win[r]));
    end

endmodule
