/* The flit and the link of the NoC library: their layouts in one place, built from numbers.
 *
 * Packets are one or more flits: the first has head=1, the last tail=1 (a packet of one flit
 * has both). vc is the flit's virtual channel on the link it is on: each router writes the
 * output VC it allocated to the packet, so the vc changes from hop to hop. The data of a head
 * flit begins with the route, DC_NOC_HEAD_T: the destination's mesh coordinates (XY routing),
 * then the rest of the data; body and tail flits carry data only.
 * A link joins an output port to the input port of the next router, in one direction: its
 * forward wires (DC_NOC_LINK_FWD_T: valid, the flit) and its backward wires (DC_NOC_LINK_BWD_T:
 * valid, vc: a credit for that VC of the receiver's input buffer).
 * Signals that travel together become a struct: a flit with valid (DC_NOC_FLIT_VLD_T: also the
 * link's forward wires), a VC number with valid (DC_NOC_VC_VLD_T: also the link's backward
 * wires, and a VC grant), the state of an input VC (DC_NOC_VC_IN_STATE_T); a lone control bit
 * stays a bit.
 * The blocks of the library build their types from their parameters, as localparam types in
 * the parameter list (localparam type FLIT_T = `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH)); a design
 * does the same in its configuration package, with the same numbers:
 *     `include "../block/noc/dark_circuit_noc.svh"
 *     typedef `DC_NOC_FLIT_T(`DC_NOC_VC_WIDTH(4), 32) flit_t;
 *     typedef `DC_NOC_LINK_FWD_T(`DC_NOC_VC_WIDTH(4), 32) link_fwd_t;
 * Macros, because a package can not take parameters. The include path goes through
 * rtl/lib/macro, the one include directory of the build (Icarus and Verilator do not look in
 * the directory of the including file), so the NoC keeps its files in rtl/lib/block/noc.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`ifndef DARK_CIRCUIT_NOC_SVH
`define DARK_CIRCUIT_NOC_SVH

// Bits of the vc field for num_vcs virtual channels (at least 1).
`define DC_NOC_VC_WIDTH(num_vcs) (((num_vcs) > 1) ? $clog2(num_vcs) : 1)

// A flit: head, tail, vc, data.
`define DC_NOC_FLIT_T(vc_width, data_width) \
    struct packed {                         \
        logic                    head;      \
        logic                    tail;      \
        logic [(vc_width)-1:0]   vc;        \
        logic [(data_width)-1:0] data;      \
    }

// Bits of a flit.
`define DC_NOC_FLIT_WIDTH(vc_width, data_width) (2 + (vc_width) + (data_width))

// The data of a head flit: the route first (its high bits), then the rest of the data.
`define DC_NOC_HEAD_T(x_width, y_width, data_width)       \
    struct packed {                                       \
        logic [(x_width)-1:0]                     dest_x; \
        logic [(y_width)-1:0]                     dest_y; \
        logic [(data_width)-(x_width)-(y_width)-1:0] rest;  \
    }

// Bits of an output port number for num_ports ports (at least 1).
`define DC_NOC_PORT_WIDTH(num_ports) (((num_ports) > 1) ? $clog2(num_ports) : 1)

// A flit with valid.
`define DC_NOC_FLIT_VLD_T(vc_width, data_width)        \
    struct packed {                                    \
        logic                                 valid;   \
        `DC_NOC_FLIT_T(vc_width, data_width)  flit;    \
    }

// A VC number with valid.
`define DC_NOC_VC_VLD_T(vc_width)            \
    struct packed {                          \
        logic                  valid;        \
        logic [(vc_width)-1:0] vc;           \
    }

// Forward wires of a link: valid, the flit.
`define DC_NOC_LINK_FWD_T(vc_width, data_width) `DC_NOC_FLIT_VLD_T(vc_width, data_width)

// Backward wires of a link: valid, vc: a slot of that VC in the receiver's input buffer is free.
`define DC_NOC_LINK_BWD_T(vc_width) `DC_NOC_VC_VLD_T(vc_width)

// The state of an input VC (NocVirtChIn), for the allocators: state (NocPkg::VC_IDLE,
// VC_WAIT_VC, VC_ACTIVE), the packet's output port and output VC (from its head to its tail).
`define DC_NOC_VC_IN_STATE_T(port_width, vc_width)   \
    struct packed {                                  \
        logic [1:0]              state;              \
        logic [(port_width)-1:0] route;              \
        logic [(vc_width)-1:0]   out_vc;             \
    }

`endif
