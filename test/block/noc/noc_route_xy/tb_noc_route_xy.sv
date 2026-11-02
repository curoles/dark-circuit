/* Test of NocRouteXy: every destination, for routers in both corners of the system (its edges
 * in x and y, where a comparison with the router's coordinate could be constant), one inside
 * it, and one with other coordinate widths. The expected port by the XY rule on integers: east
 * or west until the destination's x, then north or south, then local. Stops at the first
 * mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "../block/noc/dark_circuit_noc.svh"

module TbNocRouteXyCheck #(
    parameter X_WIDTH = 2,
    parameter Y_WIDTH = 2,
    parameter MY_X    = 0,
    parameter MY_Y    = 0
)(
    output logic done
);
    localparam PORT_WIDTH = `DC_NOC_PORT_WIDTH(NocPkg::MESH_PORTS);

    logic [X_WIDTH-1:0]    dest_x;
    logic [Y_WIDTH-1:0]    dest_y;
    wire  [PORT_WIDTH-1:0] port;

    NocRouteXy #(.X_WIDTH(X_WIDTH), .Y_WIDTH(Y_WIDTH), .MY_X(MY_X), .MY_Y(MY_Y)) u_route(
        .dest_x, .dest_y, .port);

    // The XY rule on integers.
    function automatic integer expected(input integer x, input integer y);
        if (x > MY_X) return NocPkg::PORT_EAST;
        if (x < MY_X) return NocPkg::PORT_WEST;
        if (y > MY_Y) return NocPkg::PORT_NORTH;
        if (y < MY_Y) return NocPkg::PORT_SOUTH;
        return NocPkg::PORT_LOCAL;
    endfunction

    initial begin
        done = 1'b0;
        for (int x = 0; x < (1 << X_WIDTH); x++)
            for (int y = 0; y < (1 << Y_WIDTH); y++) begin
                dest_x = X_WIDTH'(x);
                dest_y = Y_WIDTH'(y);
                #1;
                if (int'(port) != expected(x, y))
                    $fatal(1, "NocRouteXy at (%0d, %0d): to (%0d, %0d) port %0d, expected %0d",
                           MY_X, MY_Y, x, y, port, expected(x, y));
            end
        done = 1'b1;
    end
endmodule

module TbNocRouteXy;
    wire done_corner_0;
    wire done_corner_3;
    wire done_inside;
    wire done_widths;

    TbNocRouteXyCheck #(.MY_X(0), .MY_Y(0)) u_check_corner_0(.done(done_corner_0));
    TbNocRouteXyCheck #(.MY_X(3), .MY_Y(3)) u_check_corner_3(.done(done_corner_3));
    TbNocRouteXyCheck #(.MY_X(1), .MY_Y(2)) u_check_inside(.done(done_inside));
    TbNocRouteXyCheck #(.X_WIDTH(3), .Y_WIDTH(1), .MY_X(5), .MY_Y(0)) u_check_widths(
        .done(done_widths));

    initial begin
        wait (done_corner_0 && done_corner_3 && done_inside && done_widths);
        $display("PASS");
        $finish;
    end
endmodule
