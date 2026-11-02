/* XY route of a 2D mesh, made of parts and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there). dest >= MY is the
 * carry out of dest + ~MY + 1 (no borrow), dest != MY a CmpNe, for x and for y; then Mux2s
 * pick the port, x first: west below MY_X, east above it, else the y step (south, north,
 * here).
 *
 *   dest_x --+--> RippleCarryAdder: dest_x + ~MY_X + 1, its carry out --> x_ge
 *            +--> CmpNe MY_X ----------------------------------------> x_ne
 *   dest_y --+--> the same with MY_Y ---------------------------------> y_ge, y_ne
 *
 *   LOCAL  --> in0 +------+
 *   NORTH  --> in1 | Mux2 |--> y_pick --> in1 +------+
 *          y_ne -> +------+    SOUTH ---> in0 | Mux2 |--> y_port --> in0 +------+
 *                                    y_ge --> +------+   EAST -----> in1 | Mux2 |--> x_pick
 *                                                              x_ne ---> +------+       |
 *                                                     WEST --> in0 +------+             |
 *                                                     x_pick ->in1 | Mux2 |--> port <---+
 *                                                         x_ge --> +------+
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "../block/noc/dark_circuit_noc.svh"

module NocRouteXy #(
    parameter  X_WIDTH    = 2,                  // mesh coordinates
    parameter  Y_WIDTH    = 2,
    parameter  MY_X       = 0,                  // where the router is
    parameter  MY_Y       = 0,
    localparam PORT_WIDTH = `DC_NOC_PORT_WIDTH(NocPkg::MESH_PORTS)
)(
    input  wire [X_WIDTH-1:0]    dest_x,        // the destination of the head flit
    input  wire [Y_WIDTH-1:0]    dest_y,
    output wire [PORT_WIDTH-1:0] port           // its output port
);
    localparam [X_WIDTH-1:0]    X     = X_WIDTH'(MY_X);
    localparam [Y_WIDTH-1:0]    Y     = Y_WIDTH'(MY_Y);
    localparam [PORT_WIDTH-1:0] LOCAL = PORT_WIDTH'(NocPkg::PORT_LOCAL);
    localparam [PORT_WIDTH-1:0] NORTH = PORT_WIDTH'(NocPkg::PORT_NORTH);
    localparam [PORT_WIDTH-1:0] SOUTH = PORT_WIDTH'(NocPkg::PORT_SOUTH);
    localparam [PORT_WIDTH-1:0] WEST  = PORT_WIDTH'(NocPkg::PORT_WEST);
    localparam [PORT_WIDTH-1:0] EAST  = PORT_WIDTH'(NocPkg::PORT_EAST);

    wire                  x_ge;                 // dest_x >= MY_X
    wire                  x_ne;
    wire                  y_ge;
    wire                  y_ne;
    wire [PORT_WIDTH-1:0] y_pick;               // dest_y >= MY_Y: north or here
    wire [PORT_WIDTH-1:0] y_port;               // the y step: south, north or here
    wire [PORT_WIDTH-1:0] x_pick;               // dest_x >= MY_X: east or the y step
    // Only the carries of the subtractions are used.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [X_WIDTH-1:0]    x_diff;
    wire [Y_WIDTH-1:0]    y_diff;
    /* verilator lint_on UNUSEDSIGNAL */

    RippleCarryAdder #(.WIDTH(X_WIDTH)) u_ripple_carry_adder_x(
        .in1(dest_x), .in2(~X), .ci(1'b1), .co(x_ge), .sum(x_diff));
    CmpNe #(X_WIDTH) u_cmp_ne_x(.in1(dest_x), .in2(X), .ne(x_ne));
    RippleCarryAdder #(.WIDTH(Y_WIDTH)) u_ripple_carry_adder_y(
        .in1(dest_y), .in2(~Y), .ci(1'b1), .co(y_ge), .sum(y_diff));
    CmpNe #(Y_WIDTH) u_cmp_ne_y(.in1(dest_y), .in2(Y), .ne(y_ne));

    Mux2 #(PORT_WIDTH) u_mux2_y_pick(.in0(LOCAL),  .in1(NORTH),  .sel(y_ne), .out(y_pick));
    Mux2 #(PORT_WIDTH) u_mux2_y_port(.in0(SOUTH),  .in1(y_pick), .sel(y_ge), .out(y_port));
    Mux2 #(PORT_WIDTH) u_mux2_x_pick(.in0(y_port), .in1(EAST),   .sel(x_ne), .out(x_pick));
    Mux2 #(PORT_WIDTH) u_mux2_port  (.in0(WEST),   .in1(x_pick), .sel(x_ge), .out(port));

endmodule
