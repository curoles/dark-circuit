/* NoC mesh, one slice: X_SIZE x Y_SIZE routers (NocVirtChRouter), made of NoC blocks (behave
 * or struct, whichever versions the flist has).
 *
 * Router (x, y) of the slice is at the global coordinates (X0 + x, Y0 + y): X_WIDTH and Y_WIDTH
 * cover the whole system, so slices stitched edge to edge form one bigger mesh and XY routing
 * crosses them with no new flit fields. Neighbors are joined by two links, one each way, each a
 * NocLinkWire of LINK_DELAY clocks, built by its sending router: (x, y) east to (x + 1, y) west,
 * west to (x - 1, y) east, north (y + 1) to its south, south (y - 1) to its north. The ports of
 * the routers on the slice's edges come out as the edge links, per side, one per router on it
 * (north_*[x] of row Y_SIZE - 1, south_*[x] of row 0, west_*[y] of column 0, east_*[y] of
 * column X_SIZE - 1): a top joins them to another slice, through a NocLinkWire of its own (a
 * longer one between chips), or ties them off (no flit in, no credit back). Every router's local
 * port comes out as local_*[x + y * X_SIZE], for the network interface of its node.
 *
 *   y ^             north edge: north_*[x]
 *     |       +-----+        +-----+        +-----+
 *     |  west | 0,2 |<======>| 1,2 |<======>| 2,2 | east
 *     |  edge +-----+        +-----+        +-----+ edge
 *     |         ^ v            ^ v            ^ v
 *     |       +-----+        +-----+        +-----+
 *     | west_ | 0,1 |<======>| 1,1 |<======>| 2,1 | east_
 *     | *[y]  +-----+        +-----+        +-----+ *[y]
 *     |         ^ v            ^ v            ^ v
 *     |       +-----+        +-----+        +-----+
 *     |       | 0,0 |<======>| 1,0 |<======>| 2,0 |
 *     |       +-----+        +-----+        +-----+
 *     +------------->  south edge: south_*[x]         x
 *   <====>, ^ v: two NocLinkWire, one each way; each router: local_*[x + y * X_SIZE]
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"
`include "../block/noc/dark_circuit_noc.svh"

module NocMesh #(
    parameter  X_SIZE     = 3,                  // routers in x (columns)
    parameter  Y_SIZE     = 3,                  // routers in y (rows)
    parameter  X0         = 0,                  // global coordinates of router (0, 0)
    parameter  Y0         = 0,
    parameter  X_WIDTH    = 2,                  // global coordinates: the whole system
    parameter  Y_WIDTH    = 2,
    parameter  NUM_VCS    = 2,                  // virtual channels on every link
    parameter  BUF_DEPTH  = 4,                  // flits of an input buffer per VC
    parameter  DATA_WIDTH = 32,                 // data of a flit
    parameter  LINK_DELAY = 1,                  // clocks of each link between two routers
    localparam NODES      = X_SIZE * Y_SIZE,
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS),
    localparam type LINK_FWD_T = `DC_NOC_LINK_FWD_T(VC_WIDTH, DATA_WIDTH),
    localparam type LINK_BWD_T = `DC_NOC_LINK_BWD_T(VC_WIDTH)
)(
    input  wire                         clk,
    input  wire                         rst_n,          // synchronous reset, active low

    // Local ports, node (x, y) at x + y * X_SIZE: into the mesh and out of it
    input  wire LINK_FWD_T [NODES-1:0]  local_in_fwd,   // from the node: flits
    output wire LINK_BWD_T [NODES-1:0]  local_in_bwd,   //   to it: credits
    output wire LINK_FWD_T [NODES-1:0]  local_out_fwd,  // to the node: flits
    input  wire LINK_BWD_T [NODES-1:0]  local_out_bwd,  //   from it: credits

    // Edge links, per side: in = into the slice, out = out of it
    input  wire LINK_FWD_T [X_SIZE-1:0] north_in_fwd,
    output wire LINK_BWD_T [X_SIZE-1:0] north_in_bwd,
    output wire LINK_FWD_T [X_SIZE-1:0] north_out_fwd,
    input  wire LINK_BWD_T [X_SIZE-1:0] north_out_bwd,
    input  wire LINK_FWD_T [X_SIZE-1:0] south_in_fwd,
    output wire LINK_BWD_T [X_SIZE-1:0] south_in_bwd,
    output wire LINK_FWD_T [X_SIZE-1:0] south_out_fwd,
    input  wire LINK_BWD_T [X_SIZE-1:0] south_out_bwd,
    input  wire LINK_FWD_T [Y_SIZE-1:0] west_in_fwd,
    output wire LINK_BWD_T [Y_SIZE-1:0] west_in_bwd,
    output wire LINK_FWD_T [Y_SIZE-1:0] west_out_fwd,
    input  wire LINK_BWD_T [Y_SIZE-1:0] west_out_bwd,
    input  wire LINK_FWD_T [Y_SIZE-1:0] east_in_fwd,
    output wire LINK_BWD_T [Y_SIZE-1:0] east_in_bwd,
    output wire LINK_FWD_T [Y_SIZE-1:0] east_out_fwd,
    input  wire LINK_BWD_T [Y_SIZE-1:0] east_out_bwd
);
    localparam N     = NocPkg::MESH_PORTS;
    localparam LOCAL = NocPkg::PORT_LOCAL;
    localparam NORTH = NocPkg::PORT_NORTH;
    localparam SOUTH = NocPkg::PORT_SOUTH;
    localparam WEST  = NocPkg::PORT_WEST;
    localparam EAST  = NocPkg::PORT_EAST;

    `DC_STATIC_ASSERT(a_size, X_SIZE >= 1 && Y_SIZE >= 1)
    `DC_STATIC_ASSERT(a_x_fits, X0 + X_SIZE <= (1 << X_WIDTH))
    `DC_STATIC_ASSERT(a_y_fits, Y0 + Y_SIZE <= (1 << Y_WIDTH))

    // Per router, its links: in = into it, out = out of it.
    wire LINK_FWD_T [NODES-1:0][N-1:0] in_fwd;
    wire LINK_BWD_T [NODES-1:0][N-1:0] in_bwd;
    wire LINK_FWD_T [NODES-1:0][N-1:0] out_fwd;
    wire LINK_BWD_T [NODES-1:0][N-1:0] out_bwd;

    for (genvar y = 0; y < Y_SIZE; y++) begin: g_row
        for (genvar x = 0; x < X_SIZE; x++) begin: g_col
            localparam n = x + y * X_SIZE;      // this router

            NocVirtChRouter #(.NUM_VCS(NUM_VCS), .BUF_DEPTH(BUF_DEPTH), .X_WIDTH(X_WIDTH),
                              .Y_WIDTH(Y_WIDTH), .DATA_WIDTH(DATA_WIDTH), .MY_X(X0 + x),
                              .MY_Y(Y0 + y)) u_router(
                .clk, .rst_n, .in_fwd(in_fwd[n]), .in_bwd(in_bwd[n]), .out_fwd(out_fwd[n]),
                .out_bwd(out_bwd[n]));

            // Local port: the node.
            assign in_fwd[n][LOCAL]  = local_in_fwd[n];
            assign local_in_bwd[n]   = in_bwd[n][LOCAL];
            assign local_out_fwd[n]  = out_fwd[n][LOCAL];
            assign out_bwd[n][LOCAL] = local_out_bwd[n];

            // East: a link to (x + 1, y), or the east edge (out and in).
            if (x < X_SIZE - 1) begin: g_east_link
                NocLinkWire #(.DELAY(LINK_DELAY), .NUM_VCS(NUM_VCS), .DATA_WIDTH(DATA_WIDTH))
                    u_link(.clk, .rst_n, .src_fwd(out_fwd[n][EAST]), .src_bwd(out_bwd[n][EAST]),
                           .dst_fwd(in_fwd[n + 1][WEST]), .dst_bwd(in_bwd[n + 1][WEST]));
            end else begin: g_east_edge
                assign east_out_fwd[y]  = out_fwd[n][EAST];
                assign out_bwd[n][EAST] = east_out_bwd[y];
                assign in_fwd[n][EAST]  = east_in_fwd[y];
                assign east_in_bwd[y]   = in_bwd[n][EAST];
            end

            // West: a link to (x - 1, y), or the west edge.
            if (x > 0) begin: g_west_link
                NocLinkWire #(.DELAY(LINK_DELAY), .NUM_VCS(NUM_VCS), .DATA_WIDTH(DATA_WIDTH))
                    u_link(.clk, .rst_n, .src_fwd(out_fwd[n][WEST]), .src_bwd(out_bwd[n][WEST]),
                           .dst_fwd(in_fwd[n - 1][EAST]), .dst_bwd(in_bwd[n - 1][EAST]));
            end else begin: g_west_edge
                assign west_out_fwd[y]  = out_fwd[n][WEST];
                assign out_bwd[n][WEST] = west_out_bwd[y];
                assign in_fwd[n][WEST]  = west_in_fwd[y];
                assign west_in_bwd[y]   = in_bwd[n][WEST];
            end

            // North: a link to (x, y + 1), or the north edge.
            if (y < Y_SIZE - 1) begin: g_north_link
                NocLinkWire #(.DELAY(LINK_DELAY), .NUM_VCS(NUM_VCS), .DATA_WIDTH(DATA_WIDTH))
                    u_link(.clk, .rst_n, .src_fwd(out_fwd[n][NORTH]), .src_bwd(out_bwd[n][NORTH]),
                           .dst_fwd(in_fwd[n + X_SIZE][SOUTH]),
                           .dst_bwd(in_bwd[n + X_SIZE][SOUTH]));
            end else begin: g_north_edge
                assign north_out_fwd[x]  = out_fwd[n][NORTH];
                assign out_bwd[n][NORTH] = north_out_bwd[x];
                assign in_fwd[n][NORTH]  = north_in_fwd[x];
                assign north_in_bwd[x]   = in_bwd[n][NORTH];
            end

            // South: a link to (x, y - 1), or the south edge.
            if (y > 0) begin: g_south_link
                NocLinkWire #(.DELAY(LINK_DELAY), .NUM_VCS(NUM_VCS), .DATA_WIDTH(DATA_WIDTH))
                    u_link(.clk, .rst_n, .src_fwd(out_fwd[n][SOUTH]), .src_bwd(out_bwd[n][SOUTH]),
                           .dst_fwd(in_fwd[n - X_SIZE][NORTH]),
                           .dst_bwd(in_bwd[n - X_SIZE][NORTH]));
            end else begin: g_south_edge
                assign south_out_fwd[x]  = out_fwd[n][SOUTH];
                assign out_bwd[n][SOUTH] = south_out_bwd[x];
                assign in_fwd[n][SOUTH]  = south_in_fwd[x];
                assign south_in_bwd[x]   = in_bwd[n][SOUTH];
            end
        end
    end

endmodule
