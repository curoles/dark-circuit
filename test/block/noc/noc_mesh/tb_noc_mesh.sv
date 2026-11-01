/* Test of NocMesh: packets between the nodes of one slice.
 *
 * Every node has a network interface as the test sees it: a sender on its local input (a credit
 * count per VC, a new packet only on a VC whose last tail went, a flit of a VC with a credit in
 * most clocks, packets of 1 to 4 flits to random nodes of the slice) and a receiver on its local
 * output (a credit back for each flit, 1 to 3 clocks later). The edges are tied off: no flit
 * comes in, no credit goes back; every destination is in the slice, so no flit may leave by an
 * edge. Every flit carries its packet's id. Checked: a packet arrives at its destination node;
 * on a node's VC its flits come in order, head to tail (wormhole); a receiver never holds more
 * than BUF_DEPTH flits of a VC; a sender never gets more credits than it spent; after the run
 * every packet arrives. First a lone packet of two flits from router (0, 0) to the opposite
 * corner measures the latency: its head comes out 3 clocks per router on its way plus LINK_DELAY
 * per link after it went in, its tail a clock later. Every case must happen: packets from and to
 * every node. A 3 x 3 slice at (0, 0) with links of 1 clock and 2 VCs, and a 3 x 2 slice at
 * (1, 1) with links of 2 clocks and 3 VCs; Verilator 10000 clocks of traffic each, Icarus 40.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "../block/noc/dark_circuit_noc.svh"

module TbNocMeshCheck #(
    parameter X_SIZE     = 3,
    parameter Y_SIZE     = 3,
    parameter X0         = 0,
    parameter Y0         = 0,
    parameter NUM_VCS    = 2,
    parameter LINK_DELAY = 1
)(
    input  wire  clk,
    output logic done
);
    localparam NODES      = X_SIZE * Y_SIZE;
    localparam BUF_DEPTH  = 2;
    localparam X_WIDTH    = 2;
    localparam Y_WIDTH    = 2;
    localparam DATA_WIDTH = 24;
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS);
    localparam ID_WIDTH   = DATA_WIDTH - X_WIDTH - Y_WIDTH;     // a head's id; a body's: 20 + 4
    localparam MAX_PKTS   = 40000;
    localparam Q          = 16;                                 // credits waiting per receiver
    // The lone packet, (0, 0) to the opposite corner: routers and links on its way.
    localparam HOPS       = X_SIZE - 1 + Y_SIZE - 1;
    localparam HEAD_LAT   = 3 * (HOPS + 1) + LINK_DELAY * HOPS;
`ifdef VERILATOR
    localparam N_CLOCKS   = 10000;
`else
    localparam N_CLOCKS   = 40;
`endif

    typedef `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH)            flit_t;
    typedef `DC_NOC_HEAD_T(X_WIDTH, Y_WIDTH, DATA_WIDTH)    head_t;
    typedef `DC_NOC_LINK_FWD_T(VC_WIDTH, DATA_WIDTH)        link_fwd_t;
    typedef `DC_NOC_LINK_BWD_T(VC_WIDTH)                    link_bwd_t;

    logic                    rst_n;
    link_fwd_t [NODES-1:0]   local_in_fwd;
    link_bwd_t [NODES-1:0]   local_in_bwd;
    link_fwd_t [NODES-1:0]   local_out_fwd;
    link_bwd_t [NODES-1:0]   local_out_bwd;
    link_bwd_t [X_SIZE-1:0]  north_in_bwd;
    link_fwd_t [X_SIZE-1:0]  north_out_fwd;
    link_bwd_t [X_SIZE-1:0]  south_in_bwd;
    link_fwd_t [X_SIZE-1:0]  south_out_fwd;
    link_bwd_t [Y_SIZE-1:0]  west_in_bwd;
    link_fwd_t [Y_SIZE-1:0]  west_out_fwd;
    link_bwd_t [Y_SIZE-1:0]  east_in_bwd;
    link_fwd_t [Y_SIZE-1:0]  east_out_fwd;

    // The edges tied off: no flit in, no credit back.
    NocMesh #(.X_SIZE(X_SIZE), .Y_SIZE(Y_SIZE), .X0(X0), .Y0(Y0), .X_WIDTH(X_WIDTH),
              .Y_WIDTH(Y_WIDTH), .NUM_VCS(NUM_VCS), .BUF_DEPTH(BUF_DEPTH),
              .DATA_WIDTH(DATA_WIDTH), .LINK_DELAY(LINK_DELAY)) u_mesh(
        .clk, .rst_n, .local_in_fwd, .local_in_bwd, .local_out_fwd, .local_out_bwd,
        .north_in_fwd('0), .north_in_bwd, .north_out_fwd, .north_out_bwd('0),
        .south_in_fwd('0), .south_in_bwd, .south_out_fwd, .south_out_bwd('0),
        .west_in_fwd('0),  .west_in_bwd,  .west_out_fwd,  .west_out_bwd('0),
        .east_in_fwd('0),  .east_in_bwd,  .east_out_fwd,  .east_out_bwd('0));

    // Packets, by id.
    integer pk_dest [MAX_PKTS];         // the node it goes to
    integer pk_len  [MAX_PKTS];
    logic   pk_done [MAX_PKTS];
    integer n_pkts;
    integer n_done;
    // Senders, per node and VC.
    integer s_pkt     [NODES][NUM_VCS]; // the packet being sent, -1: none
    integer s_idx     [NODES][NUM_VCS];
    integer credits   [NODES][NUM_VCS];
    logic   sending;
    // Receivers, per node and VC; per node the credits waiting.
    integer r_pkt     [NODES][NUM_VCS];
    integer r_idx     [NODES][NUM_VCS];
    integer held      [NODES][NUM_VCS];
    integer cq_vc     [NODES][Q];
    integer cq_due    [NODES][Q];
    integer cq_head   [NODES];
    integer cq_count  [NODES];
    integer seed;
    integer k;

    integer n_from [NODES];
    integer n_to   [NODES];

    // A new packet to node d: its id.
    function automatic integer new_packet(input integer d, input integer len);
        if (n_pkts >= MAX_PKTS)
            $fatal(1, "Mesh %0dx%0d: more than %0d packets", X_SIZE, Y_SIZE, MAX_PKTS);
        pk_dest[n_pkts] = d;
        pk_len[n_pkts]  = len;
        pk_done[n_pkts] = 1'b0;
        n_pkts          = n_pkts + 1;
        return n_pkts - 1;
    endfunction

    // Flit idx of packet id on VC v; the head carries the destination node's global coordinates.
    // (Only the bits of the fields are used of the numbers.)
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic flit_t make_flit(input integer id, input integer idx, input integer v);
        flit_t f;
        head_t h;
        f      = '0;
        f.head = (idx == 0);
        f.tail = (idx == pk_len[id] - 1);
        f.vc   = VC_WIDTH'(v);
        if (idx == 0) begin
            h        = '0;
            h.dest_x = X_WIDTH'(X0 + pk_dest[id] % X_SIZE);
            h.dest_y = Y_WIDTH'(Y0 + pk_dest[id] / X_SIZE);
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

    // The sender of node s sends flit f of its VC v (with a credit).
    task automatic send(input integer s, input integer v, input flit_t f);
        link_fwd_t l;
        l.valid         = 1'b1;
        l.flit          = f;
        local_in_fwd[s] = l;
        credits[s][v]   = credits[s][v] - 1;
        s_idx[s][v]     = s_idx[s][v] + 1;
        if (f.tail)
            s_pkt[s][v] = -1;
        n_from[s] = n_from[s] + 1;
    endtask
    /* verilator lint_on UNUSEDSIGNAL */

    // After the edge: each sender a flit, each receiver a credit that is due.
    task automatic drive;
        integer    v;
        link_bwd_t b;
        local_in_fwd  = '0;
        local_out_bwd = '0;
        for (int s = 0; s < NODES; s++) begin
            v = {$random(seed)} % NUM_VCS;
            if ({$random(seed)} % 10 < 6 && credits[s][v] > 0) begin
                if (s_pkt[s][v] < 0 && sending) begin
                    s_pkt[s][v] = new_packet({$random(seed)} % NODES, 1 + {$random(seed)} % 4);
                    s_idx[s][v] = 0;
                    send(s, v, make_flit(s_pkt[s][v], 0, v));
                end else if (s_pkt[s][v] >= 0)
                    send(s, v, make_flit(s_pkt[s][v], s_idx[s][v], v));
            end
        end
        for (int d = 0; d < NODES; d++)
            if (cq_count[d] > 0 && cq_due[d][cq_head[d]] <= k) begin
                b.valid          = 1'b1;
                b.vc             = VC_WIDTH'(cq_vc[d][cq_head[d]]);
                local_out_bwd[d] = b;
                held[d][cq_vc[d][cq_head[d]]] = held[d][cq_vc[d][cq_head[d]]] - 1;
                cq_head[d]  = (cq_head[d] + 1) % Q;
                cq_count[d] = cq_count[d] - 1;
            end
    endtask

    // A flit f comes out at node d.
    task automatic receive(input integer d, input flit_t f);
        integer w;
        integer id;
        w  = int'(f.vc);
        id = id_of(f);
        held[d][w] = held[d][w] + 1;
        if (held[d][w] > BUF_DEPTH)
            $fatal(1, "Mesh %0dx%0d: node %0d VC %0d: %0d flits, more than its credits", X_SIZE,
                   Y_SIZE, d, w, held[d][w]);
        if (cq_count[d] == Q)
            $fatal(1, "Mesh %0dx%0d: node %0d: credit queue full", X_SIZE, Y_SIZE, d);
        cq_vc[d][(cq_head[d] + cq_count[d]) % Q]  = w;
        cq_due[d][(cq_head[d] + cq_count[d]) % Q] = k + 1 + {$random(seed)} % 3;
        cq_count[d] = cq_count[d] + 1;
        if (r_pkt[d][w] < 0) begin
            if (!f.head || id >= n_pkts || pk_done[id] || pk_dest[id] != d)
                $fatal(1, "Mesh %0dx%0d: node %0d VC %0d: flit of packet %0d, expected a head for it",
                       X_SIZE, Y_SIZE, d, w, id);
            r_pkt[d][w] = id;
            r_idx[d][w] = 0;
        end else if (f.head || id != r_pkt[d][w] || int'(f.data[3:0]) != r_idx[d][w])
            $fatal(1, "Mesh %0dx%0d: node %0d VC %0d: flit %0d of packet %0d, expected flit %0d of %0d",
                   X_SIZE, Y_SIZE, d, w, int'(f.data[3:0]), id, r_idx[d][w], r_pkt[d][w]);
        r_idx[d][w] = r_idx[d][w] + 1;
        if (f.tail) begin
            if (r_idx[d][w] != pk_len[id])
                $fatal(1, "Mesh %0dx%0d: packet %0d ended after %0d flits, has %0d", X_SIZE,
                       Y_SIZE, id, r_idx[d][w], pk_len[id]);
            pk_done[id] = 1'b1;
            r_pkt[d][w] = -1;
            n_done      = n_done + 1;
            n_to[d]     = n_to[d] + 1;
        end
    endtask

    // Before the edge: the local outputs, the credits to the senders, the edges quiet.
    task automatic check;
        link_fwd_t l;
        link_bwd_t b;
        for (int d = 0; d < NODES; d++) begin
            l = local_out_fwd[d];
            if (l.valid)
                receive(d, l.flit);
            b = local_in_bwd[d];
            if (b.valid) begin
                credits[d][b.vc] = credits[d][b.vc] + 1;
                if (credits[d][b.vc] > BUF_DEPTH)
                    $fatal(1, "Mesh %0dx%0d: node %0d VC %0d: %0d credits, more than spent",
                           X_SIZE, Y_SIZE, d, b.vc, credits[d][b.vc]);
            end
        end
        for (int x = 0; x < X_SIZE; x++) begin
            l = north_out_fwd[x];
            b = north_in_bwd[x];
            if (l.valid || b.valid)
                $fatal(1, "Mesh %0dx%0d: traffic on the north edge at %0d", X_SIZE, Y_SIZE, x);
            l = south_out_fwd[x];
            b = south_in_bwd[x];
            if (l.valid || b.valid)
                $fatal(1, "Mesh %0dx%0d: traffic on the south edge at %0d", X_SIZE, Y_SIZE, x);
        end
        for (int y = 0; y < Y_SIZE; y++) begin
            l = west_out_fwd[y];
            b = west_in_bwd[y];
            if (l.valid || b.valid)
                $fatal(1, "Mesh %0dx%0d: traffic on the west edge at %0d", X_SIZE, Y_SIZE, y);
            l = east_out_fwd[y];
            b = east_in_bwd[y];
            if (l.valid || b.valid)
                $fatal(1, "Mesh %0dx%0d: traffic on the east edge at %0d", X_SIZE, Y_SIZE, y);
        end
    endtask

    // The lone packet: two flits from node 0 to the last node; the clocks they come out.
    task automatic lone_packet;
        integer    id;
        integer    head_out;
        integer    tail_out;
        link_fwd_t l;
        id       = new_packet(NODES - 1, 2);
        head_out = -1;
        tail_out = -1;
        for (int c = 0; c < HEAD_LAT + 10; c++) begin
            local_in_fwd  = '0;
            local_out_bwd = '0;
            if (c < 2) begin
                s_pkt[0][0] = id;
                send(0, 0, make_flit(id, c, 0));
            end
            #1;
            l = local_out_fwd[NODES - 1];
            if (l.valid && l.flit.head) head_out = c;
            if (l.valid && l.flit.tail) tail_out = c;
            check();
            k = k + 1;
            @(negedge clk);
        end
        $display("Mesh %0dx%0d, links of %0d: lone packet, %0d hops: head out after %0d, tail %0d later",
                 X_SIZE, Y_SIZE, LINK_DELAY, HOPS, head_out, tail_out - head_out);
        if (head_out != HEAD_LAT || tail_out != head_out + 1 || !pk_done[id])
            $fatal(1, "Mesh %0dx%0d: lone packet: head out at %0d, tail at %0d, expected %0d and %0d",
                   X_SIZE, Y_SIZE, head_out, tail_out, HEAD_LAT, HEAD_LAT + 1);
    endtask

    initial begin
        done    = 1'b0;
        seed    = X_SIZE * 31 + Y_SIZE * 7 + NUM_VCS;
        n_pkts  = 0;
        n_done  = 0;
        k       = 0;
        sending = 1'b0;
        for (int s = 0; s < NODES; s++) begin
            n_from[s]   = 0;
            n_to[s]     = 0;
            cq_head[s]  = 0;
            cq_count[s] = 0;
            for (int v = 0; v < NUM_VCS; v++) begin
                s_pkt[s][v]   = -1;
                s_idx[s][v]   = 0;
                credits[s][v] = BUF_DEPTH;
                r_pkt[s][v]   = -1;
                r_idx[s][v]   = 0;
                held[s][v]    = 0;
            end
        end
        rst_n         = 1'b0;
        local_in_fwd  = '0;
        local_out_bwd = '0;
        @(negedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        lone_packet();
        sending = 1'b1;
        for (int c = 0; c < N_CLOCKS + 3000 && (sending || n_done < n_pkts); c++) begin
            if (c == N_CLOCKS) sending = 1'b0;
            drive();
            #1;
            check();
            k = k + 1;
            @(negedge clk);
        end
        if (n_done != n_pkts)
            $fatal(1, "Mesh %0dx%0d: %0d of %0d packets arrived", X_SIZE, Y_SIZE, n_done, n_pkts);
        for (int s = 0; s < NODES; s++)
            if (n_from[s] == 0 || n_to[s] == 0)
                $fatal(1, "Mesh %0dx%0d: node %0d: %0d flits sent, %0d packets received", X_SIZE,
                       Y_SIZE, s, n_from[s], n_to[s]);
        $display("Mesh %0dx%0d at (%0d, %0d), links of %0d, %0d VCs: %0d packets through", X_SIZE,
                 Y_SIZE, X0, Y0, LINK_DELAY, NUM_VCS, n_done);
        // The links idle: the other check runs on.
        local_in_fwd  = '0;
        local_out_bwd = '0;
        done          = 1'b1;
    end
endmodule

module TbNocMesh;
    wire clk;
    wire done_a;
    wire done_b;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbNocMeshCheck #(.X_SIZE(3), .Y_SIZE(3), .X0(0), .Y0(0), .NUM_VCS(2), .LINK_DELAY(1))
        u_check_a(.clk, .done(done_a));
    TbNocMeshCheck #(.X_SIZE(3), .Y_SIZE(2), .X0(1), .Y0(1), .NUM_VCS(3), .LINK_DELAY(2))
        u_check_b(.clk, .done(done_b));

    initial begin
        wait (done_a && done_b);
        $display("PASS");
        $finish;
    end
endmodule
