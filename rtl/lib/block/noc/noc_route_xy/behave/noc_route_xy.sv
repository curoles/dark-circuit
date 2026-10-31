/* XY route of a 2D mesh, behavioral: the output port of a head flit at the router at (MY_X, MY_Y).
 *
 * East or west until the destination's x is reached, then north or south, then the local port
 * (NocPkg port numbers). Deadlock-free in a mesh: no packet turns from a y direction back to x.
 * West and south are "not east, not here": x < MY_X would be constant on the west edge.
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
    function automatic logic [PORT_WIDTH-1:0] xy_port(input logic [X_WIDTH-1:0] x,
                                                      input logic [Y_WIDTH-1:0] y);
        if (x >  X_WIDTH'(MY_X)) return PORT_WIDTH'(NocPkg::PORT_EAST);
        if (x != X_WIDTH'(MY_X)) return PORT_WIDTH'(NocPkg::PORT_WEST);
        if (y >  Y_WIDTH'(MY_Y)) return PORT_WIDTH'(NocPkg::PORT_NORTH);
        if (y != Y_WIDTH'(MY_Y)) return PORT_WIDTH'(NocPkg::PORT_SOUTH);
        return PORT_WIDTH'(NocPkg::PORT_LOCAL);
    endfunction

    assign port = xy_port(dest_x, dest_y);

endmodule
