/* Edge detector: edge_detected is 1 while in differs from its value at the last rising edge
 * of clk in the way EDGE asks: 0 a falling edge (in went 1 -> 0), 1 a rising edge (0 -> 1),
 * 2 any edge. For an in that changes after the rising edge of clk (synchronous to clk) that
 * is the one clock after the change.
 *
 * A DffSyncRst keeps in of the clock before (in_delayed); the edge combines in now with in
 * before: falling ~in & in_delayed, rising in & ~in_delayed, any in ^ in_delayed.
 * edge_detected is combinational from in. An asynchronous in must be synchronized first.
 * Reset (synchronous, active low) sets in_delayed to RST_VAL, the level of in when idle:
 * while in stays at it after reset, no edge is seen; in at the other level in the first
 * clock after reset is an edge.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module EdgeDetector #(
    parameter EDGE    = 0,      // 0: falling, 1: rising, 2: any
    parameter RST_VAL = 1'b0    // in_delayed in reset: the idle level of in
)(
    input  wire clk,
    input  wire rst_n,          // synchronous reset, active low
    input  wire in,
    output wire edge_detected
);
    `DC_STATIC_ASSERT(a_edge_known, EDGE >= 0 && EDGE <= 2)

    wire in_delayed;    // in at the last rising edge of clk

    DffSyncRst #(.WIDTH(1), .RST_VAL(RST_VAL)) u_dff_sync_rst(
        .clk, .rst_n, .in, .out(in_delayed));

    generate
    if (EDGE == 0) begin: g_falling
        wire in_n;
        Inv  #(1) u_inv (.in(in), .out(in_n));
        And2 #(1) u_and2(.in1(in_n), .in2(in_delayed), .out(edge_detected));
    end else if (EDGE == 1) begin: g_rising
        wire in_delayed_n;
        Inv  #(1) u_inv (.in(in_delayed), .out(in_delayed_n));
        And2 #(1) u_and2(.in1(in), .in2(in_delayed_n), .out(edge_detected));
    end else begin: g_any
        Xor2 #(1) u_xor2(.in1(in), .in2(in_delayed), .out(edge_detected));
    end
    endgenerate

endmodule
