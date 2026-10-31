/* NoC library package: port numbers of a 2D mesh router. The flit: dark_circuit_noc.svh.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package NocPkg;

    // Ports of a 2D mesh router: inject/eject and the four neighbors (plain constants, not an
    // enum: Icarus gets enum constants on ports wrong).
    localparam MESH_PORTS = 5;
    localparam PORT_LOCAL = 0;
    localparam PORT_NORTH = 1;
    localparam PORT_SOUTH = 2;
    localparam PORT_WEST  = 3;
    localparam PORT_EAST  = 4;

endpackage
