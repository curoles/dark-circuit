/* NoC library package: port numbers of a 2D mesh router, the states of a virtual channel. The
 * flit, the link and the types that depend on widths: dark_circuit_noc.svh.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package NocPkg;

    // Ports of a 2D mesh router: inject/eject and the four neighbors (plain constants, not an
    // enum: Icarus gets enum constants on ports wrong).
    // Not every user needs every constant.
    /* verilator lint_off UNUSEDPARAM */
    localparam MESH_PORTS = 5;
    localparam PORT_LOCAL = 0;
    localparam PORT_NORTH = 1;
    localparam PORT_SOUTH = 2;
    localparam PORT_WEST  = 3;
    localparam PORT_EAST  = 4;

    // State of an input VC (NocVirtChIn): a packet holds its VC from its head flit to its tail
    // flit. Plain constants, not an enum: the state crosses module ports (Icarus).
    localparam logic [1:0] VC_IDLE    = 2'd0;   // no packet: waits for a head flit at the front
    localparam logic [1:0] VC_WAIT_VC = 2'd1;   // a head with its route: waits for an output VC
    localparam logic [1:0] VC_ACTIVE  = 2'd2;   // has an output VC: its flits go when allowed
    /* verilator lint_on UNUSEDPARAM */

    // State of an output VC (NocVirtChOut), for the allocators.
    typedef struct packed {
        logic free;         // no packet holds the VC: VC allocation may give it
        logic has_credit;   // the receiver has a free slot: a flit may go
    } vc_out_state_t;

endpackage
