/* The flit of the NoC library: its layout in one place, built from numbers.
 *
 * Packets are one or more flits: the first has head=1, the last tail=1 (a packet of one flit
 * has both). vc is the flit's virtual channel on the link it is on: each router writes the
 * output VC it allocated to the packet, so the vc changes from hop to hop. The data of a head
 * flit begins with the route, DC_NOC_HEAD_T: the destination's mesh coordinates (XY routing),
 * then the rest of the data; body and tail flits carry data only. The blocks of the library define
 * their types with these macros from their parameters; a design does the same in its
 * configuration package, with the same numbers:
 *     `include "../block/noc/dark_circuit_noc.svh"
 *     typedef `DC_NOC_FLIT_T(`DC_NOC_VC_WIDTH(4), 32) flit_t;
 *     typedef `DC_NOC_HEAD_T(2, 2, 32) head_t;
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

`endif
