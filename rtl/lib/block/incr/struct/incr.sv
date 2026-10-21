/* Incrementer, made of gates.
 *
 * out = in + 1, co is carry out: 1 when in is all ones (out wraps to 0).
 *
 * Fast incrementer: in is split into groups of GROUP bits, the last group may be
 * shorter. Every group computes its own +1 at the same time: bit k of the group
 * flips when all lower bits of the group are 1. A group takes its +1 only when all
 * lower groups are all ones, otherwise it passes in. Delay is about AndReduce of
 * GROUP bits, AndReduce of the group flags and Mux2, not WIDTH steps of a carry
 * chain; GROUP near sqrt(WIDTH) gives the shortest delay.
 * WIDTH=16, GROUP=4 and WIDTH=9, GROUP=3 are the old Incr16 and Incr9.
 *
 * @author    Igor Lesik
 * @copyright 2019 Igor Lesik, MIT License
 */
module Incr #(
    parameter WIDTH = 16,
    parameter GROUP = 4      // bits in group, the last group may be shorter
)(
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out,  // in + 1
    output wire             co    // carry out: in was all ones
);
    localparam GROUPS = (WIDTH + GROUP - 1) / GROUP;

    wire [GROUPS-1:0] all1;  // all1[g]: group g is all ones

    for (genvar g = 0; g < GROUPS; g++) begin : g_group
        localparam LO = g * GROUP;                                  // lowest bit of group
        localparam W  = (WIDTH - LO < GROUP) ? WIDTH - LO : GROUP;  // bits in group
        wire [W-1:0] grp_in, grp_inc;
        assign grp_in = in[LO +: W];

        // Group + 1: bit k flips when all lower bits of the group are 1.
        Inv #(1) u_inv(.in(grp_in[0]), .out(grp_inc[0]));
        for (genvar k = 1; k < W; k++) begin : g_bit
            wire lower1;
            AndReduce #(k) u_and_reduce(.in(grp_in[k-1:0]), .out(lower1));
            Xor2      #(1) u_xor2     (.in1(grp_in[k]), .in2(lower1), .out(grp_inc[k]));
        end
        AndReduce #(W) u_and_reduce_all1(.in(grp_in), .out(all1[g]));

        // Group takes its +1 when all lower groups are all ones; group 0 always does.
        if (g == 0) begin : g_first
            assign out[LO +: W] = grp_inc;
        end else begin : g_upper
            wire lower_all1;
            AndReduce #(g) u_and_reduce_lower(.in(all1[g-1:0]), .out(lower_all1));
            Mux2      #(W) u_mux2(.in0(grp_in), .in1(grp_inc), .sel(lower_all1), .out(out[LO +: W]));
        end
    end

    AndReduce #(GROUPS) u_and_reduce_co(.in(all1), .out(co));

endmodule
