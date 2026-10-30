/* Multiplexer of N inputs, made of gates: out = in[sel].
 *
 * Same ports and behavior as the behave version (see there; sel >= N is not allowed).
 *
 * A tree of Mux4 (a MUX4 cell per bit with gate/cell), two bits of sel per level, the low bits
 * first: level l groups four nodes of the level below by sel[2l+1:2l]; the inputs are level
 * 0, the root is out. The last group of a level may have fewer nodes, and since a sel that
 * reaches a missing node is not allowed, it takes the smaller gate: 3 nodes Mux3, 2 nodes
 * Mux2 on sel[2l] alone (sel[2l+1] is 0 for every allowed sel there), 1 node no gate. When
 * $clog2(N) is odd the top level has one bit of sel and at most two nodes: so it is a Mux2.
 * For example N=8 is two Mux4 and a Mux2 (the cell Mux8), N=6 a Mux4 and a Mux2 under a
 * Mux2, N=3 one Mux3.
 * The nodes are one array, level after level (node_offset gives the first of a level).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module MuxN #(
    parameter  N         = 4,               // inputs, at least 2
    parameter  WIDTH     = 1,               // bits of an input
    localparam SEL_WIDTH = $clog2(N)
)(
    input  wire [N-1:0][WIDTH-1:0] in,      // input k: in[k]
    input  wire [SEL_WIDTH-1:0]    sel,     // below N
    output wire [WIDTH-1:0]        out
);
    `DC_STATIC_ASSERT(a_two_inputs, N >= 2)

    localparam LEVELS = (SEL_WIDTH + 1) / 2;    // levels of muxes above the inputs

    // Nodes of a level: the inputs on level 0, a node per group of four below on level l.
    function automatic int node_count(input int l);
        int n;
        n = N;
        for (int m = 1; m <= l; m++)
            n = (n + 3) / 4;
        return n;
    endfunction

    function automatic int node_offset(input int l);
        int o;
        o = 0;
        for (int m = 0; m < l; m++)
            o = o + node_count(m);
        return o;
    endfunction

    localparam NODES = node_offset(LEVELS + 1);

    wire [NODES-1:0][WIDTH-1:0] node;

    for (genvar k = 0; k < N; k++) begin: g_in
        assign node[k] = in[k];
    end

    // @kb: rtl/lib/block/mux_n/design
    for (genvar l = 1; l <= LEVELS; l++) begin: g_level
        localparam BIT   = 2 * (l - 1);         // the lowest bit of sel of this level
        localparam BELOW = node_count(l - 1);
        for (genvar g = 0; g < node_count(l); g++) begin: g_node
            localparam FIRST = node_offset(l - 1) + 4 * g;    // its first node below
            localparam KIDS  = (BELOW - 4 * g < 4) ? BELOW - 4 * g : 4;
            localparam OUT   = node_offset(l) + g;
            if (KIDS == 4) begin: g_mux4
                Mux4 #(WIDTH) u_mux4(.in0(node[FIRST]), .in1(node[FIRST + 1]),
                                     .in2(node[FIRST + 2]), .in3(node[FIRST + 3]),
                                     .sel(sel[BIT +: 2]), .out(node[OUT]));
            end else if (KIDS == 3) begin: g_mux3
                Mux3 #(WIDTH) u_mux3(.in0(node[FIRST]), .in1(node[FIRST + 1]),
                                     .in2(node[FIRST + 2]), .sel(sel[BIT +: 2]),
                                     .out(node[OUT]));
            end else if (KIDS == 2) begin: g_mux2
                Mux2 #(WIDTH) u_mux2(.in0(node[FIRST]), .in1(node[FIRST + 1]), .sel(sel[BIT]),
                                     .out(node[OUT]));
            end else begin: g_pass
                assign node[OUT] = node[FIRST];
            end
        end
    end

    assign out = node[NODES - 1];

endmodule
