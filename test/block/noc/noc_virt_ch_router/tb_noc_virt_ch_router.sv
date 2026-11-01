/* Test of NocVirtChRouter: flits end to end through one router.
 *
 * The router at (1, 1) of a 4 x 4 mesh, so every output port is some destination's route. On
 * every input a sender keeps a credit count per VC (BUF_DEPTH after reset, back with each credit
 * on in_bwd) and starts a packet only on a VC whose last packet's tail went (as VC allocation
 * upstream would); it sends a flit of a VC with a credit in most clocks, the VCs in random order,
 * packets of 1 to 4 flits to random destinations. Every flit carries its packet's id: a head's
 * data is the destination and the id, a body or tail flit's data the id and its index. On every
 * output a receiver takes the flits and returns a credit for each, 1 to 3 clocks later (one per
 * clock). Checked: a packet leaves through the port of its XY route; on an output VC its flits
 * come in order, head to tail, no other packet's flit between (wormhole); a receiver never holds
 * more than BUF_DEPTH flits of a VC (the router keeps the credits); a sender never gets more
 * credits than it spent; after the run every packet arrives. First a lone packet of two flits
 * from the west to the east port measures the latency: its head leaves 3 clocks after it came
 * (buffer write; route; VC allocation; switch allocation and the crossbar), its tail a clock
 * later. Every case must happen: packets from every input, to every output, two packets
 * interleaved on one output's VCs, a sender held back by its credits, packets of four flits.
 * NUM_VCS 2 and 3; Verilator 20000 clocks of traffic, Icarus 400. Stops at the first mismatch
 * with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "../block/noc/dark_circuit_noc.svh"

module TbNocVirtChRouterCheck #(
    parameter NUM_VCS = 2
)(
    input  wire  clk,
    output logic done
);
    localparam N          = NocPkg::MESH_PORTS;
    localparam BUF_DEPTH  = 2;
    localparam X_WIDTH    = 2;
    localparam Y_WIDTH    = 2;
    localparam DATA_WIDTH = 24;
    localparam MY_X       = 1;
    localparam MY_Y       = 1;
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS);
    localparam ID_WIDTH   = DATA_WIDTH - X_WIDTH - Y_WIDTH;     // a head's id; a body's: 20 + 4
    localparam MAX_PKTS   = 40000;
    localparam Q          = 16;                                 // credits waiting per receiver
    localparam HEAD_LAT   = 3;                                  // clocks, the lone packet's head
`ifdef VERILATOR
    localparam N_CLOCKS   = 20000;
`else
    localparam N_CLOCKS   = 400;
`endif

    typedef `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH)            flit_t;
    typedef `DC_NOC_HEAD_T(X_WIDTH, Y_WIDTH, DATA_WIDTH)    head_t;
    typedef `DC_NOC_LINK_FWD_T(VC_WIDTH, DATA_WIDTH)        link_fwd_t;
    typedef `DC_NOC_LINK_BWD_T(VC_WIDTH)                    link_bwd_t;

    logic                rst_n;
    link_fwd_t [N-1:0]   in_fwd;
    link_bwd_t [N-1:0]   in_bwd;
    link_fwd_t [N-1:0]   out_fwd;
    link_bwd_t [N-1:0]   out_bwd;

    NocVirtChRouter #(.NUM_VCS(NUM_VCS), .BUF_DEPTH(BUF_DEPTH), .X_WIDTH(X_WIDTH),
                      .Y_WIDTH(Y_WIDTH), .DATA_WIDTH(DATA_WIDTH), .MY_X(MY_X), .MY_Y(MY_Y))
        u_router(.clk, .rst_n, .in_fwd, .in_bwd, .out_fwd, .out_bwd);

    // Packets, by id.
    integer pk_out  [MAX_PKTS];         // the output of its route
    integer pk_len  [MAX_PKTS];
    logic   pk_done [MAX_PKTS];
    integer n_pkts;                     // ids given
    integer n_done;
    // Senders, per input and VC.
    integer s_pkt     [N][NUM_VCS];     // the packet being sent, -1: none (a new one may start)
    integer s_idx     [N][NUM_VCS];     // index of its next flit
    integer credits   [N][NUM_VCS];
    logic   sending;                    // new packets may start
    // Receivers, per output and VC; per output the credits waiting.
    integer r_pkt     [N][NUM_VCS];     // the packet coming, -1: none
    integer r_idx     [N][NUM_VCS];     // index of its next flit
    integer held      [N][NUM_VCS];     // flits of the VC in the receiver
    integer cq_vc     [N][Q];
    integer cq_due    [N][Q];
    integer cq_head   [N];
    integer cq_count  [N];
    integer seed;
    integer k;                          // clock

    // Cases seen.
    integer n_from     [N];
    integer n_to       [N];
    integer n_interleave;               // a flit on an output VC, another VC of it mid-packet
    integer n_no_credit;                // a sender's packet held back by its credits
    integer n_four;                     // packets of four flits delivered

    // XY route of a destination seen from (MY_X, MY_Y).
    function automatic integer xy_port(input integer x, input integer y);
        if (x > MY_X) return NocPkg::PORT_EAST;
        if (x < MY_X) return NocPkg::PORT_WEST;
        if (y > MY_Y) return NocPkg::PORT_NORTH;
        if (y < MY_Y) return NocPkg::PORT_SOUTH;
        return NocPkg::PORT_LOCAL;
    endfunction

    // A new packet: its id, its route's port, its length.
    function automatic integer new_packet(input integer x, input integer y, input integer len);
        if (n_pkts >= MAX_PKTS)
            $fatal(1, "Router %0d: more than %0d packets", NUM_VCS, MAX_PKTS);
        pk_out[n_pkts]  = xy_port(x, y);
        pk_len[n_pkts]  = len;
        pk_done[n_pkts] = 1'b0;
        n_pkts          = n_pkts + 1;
        return n_pkts - 1;
    endfunction

    // Flit idx of packet id on VC v; the head carries the destination (x, y). (Only the bits of
    // the fields are used of the numbers.)
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic flit_t make_flit(input integer id, input integer idx, input integer x,
                                        input integer y, input integer v);
        flit_t f;
        head_t h;
        f      = '0;
        f.head = (idx == 0);
        f.tail = (idx == pk_len[id] - 1);
        f.vc   = VC_WIDTH'(v);
        if (idx == 0) begin
            h        = '0;
            h.dest_x = X_WIDTH'(x);
            h.dest_y = Y_WIDTH'(y);
            h.rest   = ID_WIDTH'(id);
            f.data   = h;
        end else
            f.data = {ID_WIDTH'(id), 4'(idx)};
        return f;
    endfunction

    // The id a flit carries (the rest of the flit is not used).
    function automatic integer id_of(input flit_t f);
        head_t h;
        h = f.data;
        return f.head ? int'(h.rest) : int'(f.data[DATA_WIDTH-1:4]);
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // A sender sends flit f of its VC v (with a credit). (v is an index: its high bits are 0.)
    /* verilator lint_off UNUSEDSIGNAL */
    task automatic send(input integer p, input integer v, input flit_t f);
    /* verilator lint_on UNUSEDSIGNAL */
        link_fwd_t l;
        l.valid       = 1'b1;
        l.flit        = f;
        in_fwd[p]     = l;
        credits[p][v] = credits[p][v] - 1;
        s_idx[p][v]   = s_idx[p][v] + 1;
        if (f.tail)
            s_pkt[p][v] = -1;
        n_from[p] = n_from[p] + 1;
    endtask

    // After the edge: each sender a flit, each receiver a credit that is due.
    task automatic drive;
        integer    v;
        integer    x;
        integer    y;
        link_bwd_t b;
        in_fwd  = '0;
        out_bwd = '0;
        for (int p = 0; p < N; p++) begin
            for (int w = 0; w < NUM_VCS; w++)
                if (s_pkt[p][w] >= 0 && credits[p][w] == 0)
                    n_no_credit = n_no_credit + 1;
            v = {$random(seed)} % NUM_VCS;
            if ({$random(seed)} % 10 < 7 && credits[p][v] > 0) begin
                if (s_pkt[p][v] < 0 && sending) begin
                    x           = {$random(seed)} % 4;
                    y           = {$random(seed)} % 4;
                    s_pkt[p][v] = new_packet(x, y, 1 + {$random(seed)} % 4);
                    s_idx[p][v] = 0;
                    send(p, v, make_flit(s_pkt[p][v], 0, x, y, v));
                end else if (s_pkt[p][v] >= 0)
                    send(p, v, make_flit(s_pkt[p][v], s_idx[p][v], 0, 0, v));
            end
        end
        for (int r = 0; r < N; r++)
            if (cq_count[r] > 0 && cq_due[r][cq_head[r]] <= k) begin
                b.valid     = 1'b1;
                b.vc        = VC_WIDTH'(cq_vc[r][cq_head[r]]);
                out_bwd[r]  = b;
                held[r][cq_vc[r][cq_head[r]]] = held[r][cq_vc[r][cq_head[r]]] - 1;
                cq_head[r]  = (cq_head[r] + 1) % Q;
                cq_count[r] = cq_count[r] - 1;
            end
    endtask

    // A flit f comes out of output r.
    task automatic receive(input integer r, input flit_t f);
        integer w;
        integer id;
        w  = int'(f.vc);
        id = id_of(f);
        held[r][w] = held[r][w] + 1;
        if (held[r][w] > BUF_DEPTH)
            $fatal(1, "Router %0d: output %0d VC %0d: %0d flits, more than its credits", NUM_VCS,
                   r, w, held[r][w]);
        if (cq_count[r] == Q)
            $fatal(1, "Router %0d: output %0d: credit queue full", NUM_VCS, r);
        cq_vc[r][(cq_head[r] + cq_count[r]) % Q]  = w;
        cq_due[r][(cq_head[r] + cq_count[r]) % Q] = k + 1 + {$random(seed)} % 3;
        cq_count[r] = cq_count[r] + 1;
        for (int u = 0; u < NUM_VCS; u++)
            if (u != w && r_pkt[r][u] >= 0) n_interleave = n_interleave + 1;
        if (r_pkt[r][w] < 0) begin
            if (!f.head || id >= n_pkts || pk_done[id] || pk_out[id] != r)
                $fatal(1, "Router %0d: output %0d VC %0d: flit of packet %0d, expected a head routed here",
                       NUM_VCS, r, w, id);
            r_pkt[r][w] = id;
            r_idx[r][w] = 0;
        end else if (f.head || id != r_pkt[r][w] || int'(f.data[3:0]) != r_idx[r][w])
            $fatal(1, "Router %0d: output %0d VC %0d: flit %0d of packet %0d, expected flit %0d of %0d",
                   NUM_VCS, r, w, int'(f.data[3:0]), id, r_idx[r][w], r_pkt[r][w]);
        r_idx[r][w] = r_idx[r][w] + 1;
        if (f.tail) begin
            if (r_idx[r][w] != pk_len[id])
                $fatal(1, "Router %0d: packet %0d ended after %0d flits, has %0d", NUM_VCS, id,
                       r_idx[r][w], pk_len[id]);
            pk_done[id] = 1'b1;
            r_pkt[r][w] = -1;
            n_done      = n_done + 1;
            n_to[r]     = n_to[r] + 1;
            if (pk_len[id] == 4) n_four = n_four + 1;
        end
    endtask

    // Before the edge: the outputs.
    task automatic check;
        link_fwd_t l;
        link_bwd_t b;
        for (int r = 0; r < N; r++) begin
            l = out_fwd[r];
            if (l.valid)
                receive(r, l.flit);
        end
        for (int p = 0; p < N; p++) begin
            b = in_bwd[p];
            if (b.valid) begin
                credits[p][b.vc] = credits[p][b.vc] + 1;
                if (credits[p][b.vc] > BUF_DEPTH)
                    $fatal(1, "Router %0d: input %0d VC %0d: %0d credits, more than spent",
                           NUM_VCS, p, b.vc, credits[p][b.vc]);
            end
        end
    endtask

    // The lone packet: two flits from the west to (3, 1), the east port; the clocks they leave.
    task automatic lone_packet;
        integer    id;
        integer    head_out;
        integer    tail_out;
        link_fwd_t l;
        id       = new_packet(3, 1, 2);
        head_out = -1;
        tail_out = -1;
        for (int c = 0; c < 20; c++) begin
            in_fwd  = '0;
            out_bwd = '0;
            if (c < 2) begin
                s_pkt[NocPkg::PORT_WEST][0] = id;
                send(NocPkg::PORT_WEST, 0, make_flit(id, c, 3, 1, 0));
            end
            #1;
            l = out_fwd[NocPkg::PORT_EAST];
            if (l.valid && l.flit.head) head_out = c;
            if (l.valid && l.flit.tail) tail_out = c;
            check();
            k = k + 1;
            @(negedge clk);
        end
        $display("Router %0d VCs: lone packet: head out %0d clocks after it came, tail %0d clock(s) after the head",
                 NUM_VCS, head_out, tail_out - head_out);
        if (head_out != HEAD_LAT || tail_out != head_out + 1 || !pk_done[id])
            $fatal(1, "Router %0d: lone packet: head out at %0d, tail at %0d, expected %0d and %0d",
                   NUM_VCS, head_out, tail_out, HEAD_LAT, HEAD_LAT + 1);
        // Its credits came back: the senders and receivers are as after reset.
        out_bwd = '0;
    endtask

    initial begin
        done         = 1'b0;
        seed         = NUM_VCS * 23;
        n_pkts       = 0;
        n_done       = 0;
        k            = 0;
        sending      = 1'b0;
        n_interleave = 0;
        n_no_credit  = 0;
        n_four       = 0;
        for (int p = 0; p < N; p++) begin
            n_from[p]   = 0;
            n_to[p]     = 0;
            cq_head[p]  = 0;
            cq_count[p] = 0;
            for (int v = 0; v < NUM_VCS; v++) begin
                s_pkt[p][v]   = -1;
                s_idx[p][v]   = 0;
                credits[p][v] = BUF_DEPTH;
                r_pkt[p][v]   = -1;
                r_idx[p][v]   = 0;
                held[p][v]    = 0;
            end
        end
        rst_n   = 1'b0;
        in_fwd  = '0;
        out_bwd = '0;
        @(negedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        lone_packet();
        // Traffic, then a drain until every packet arrived.
        sending = 1'b1;
        for (int c = 0; c < N_CLOCKS + 2000 && (sending || n_done < n_pkts); c++) begin
            if (c == N_CLOCKS) sending = 1'b0;
            drive();
            #1;
            check();
            k = k + 1;
            @(negedge clk);
        end
        if (n_done != n_pkts)
            $fatal(1, "Router %0d: %0d of %0d packets arrived", NUM_VCS, n_done, n_pkts);
        for (int p = 0; p < N; p++)
            if (n_from[p] == 0 || n_to[p] == 0)
                $fatal(1, "Router %0d: port %0d: %0d flits in, %0d packets out", NUM_VCS, p,
                       n_from[p], n_to[p]);
        if (n_interleave == 0 || n_no_credit == 0 || n_four == 0)
            $fatal(1, "Router %0d: cases: interleave %0d, no credit %0d, four flits %0d",
                   NUM_VCS, n_interleave, n_no_credit, n_four);
        $display("Router %0d VCs: %0d packets through", NUM_VCS, n_done);
        // The links idle: the other check runs on.
        in_fwd  = '0;
        out_bwd = '0;
        done    = 1'b1;
    end
endmodule

module TbNocVirtChRouter;
    wire clk;
    wire done_2;
    wire done_3;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbNocVirtChRouterCheck #(.NUM_VCS(2)) u_check_2(.clk, .done(done_2));
    TbNocVirtChRouterCheck #(.NUM_VCS(3)) u_check_3(.clk, .done(done_3));

    initial begin
        wait (done_2 && done_3);
        $display("PASS");
        $finish;
    end
endmodule
