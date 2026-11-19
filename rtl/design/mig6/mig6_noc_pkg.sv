/* The messages of Mig6's network on chip, for now: memory requests and their answers, on two
 * networks (a NocMesh each, one VC): requests from the PEs to the shared memory, answers
 * back (rtl/design/mig6/README.md). A message is a NoC packet of one or two flits. Its head
 * is the library's (DC_NOC_HEAD_T): the route, dest_x and dest_y, then the rest, which is
 * this package's (req_rest_t, rsp_rest_t); so the route is where the routers read it by
 * construction. A prototype: the layout may change; it moves to the library once it settles.
 *
 * Request network, 48-bit flit data:
 *
 *   head     | dest_x 2 | dest_y 2 | op 3 | src_x 2 | src_y 2 | size 3 | addr 32 | cmo 2 |
 *   WRITE    | zero 12 | data 32 | strb 4 |             the body: a second flit, the tail
 *   SC       | zero 12 | data 32 | strb 4 |             the same body as a WRITE
 *   ATOMIC   | zero 10 | operand 32 | atop 6 |
 *
 * Answer network, 39-bit flit data, one flit:
 *
 *   DATA     | dest_x 2 | dest_y 2 | op 3 | data 32 |       a READ's, an LR's, an ATOMIC's
 *   ACK      | dest_x 2 | dest_y 2 | op 3 | status 32 |     an SC's (later acknowledged writes)
 *
 * READ, LR and CBO are a head alone, WRITE, SC and ATOMIC a head and a body. LR and SC are
 * the exclusive READ and WRITE (the request channel's req_excl; the head has no bit left
 * for a flag): the shared memory keeps a reservation per PE, src, and an SC writes only
 * while its PE's holds; its ACK's status is RISC-V's SC result (SC_SUCCESS 0, SC_FAIL 1),
 * so a core writes it to rd as it comes; as AXI answers a write on B with OKAY or EXOKAY,
 * a read with data on R. An answer goes to its request's src_x, src_y. A PE's requests and
 * their answers stay in order (a network per class, one VC, XY routes), so no message
 * carries an ID. size is AXI's (1 << size bytes), atop AXI's AWATOP (AtomicPkg), cmo
 * CMO_NONE but in a CBO (CachePkg).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "../block/noc/dark_circuit_noc.svh"

package Mig6NocPkg;

    // Constants for the network interfaces and testbenches; each uses only some of them.
    /* verilator lint_off UNUSEDPARAM */

    localparam X_WIDTH    = 2;      // mesh coordinates up to 4 x 4
    localparam Y_WIDTH    = 2;
    localparam NUM_VCS    = 1;      // one VC per network: a PE's messages stay in order
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS);
    localparam ADDR_WIDTH = 32;     // byte address
    localparam DATA_WIDTH = 32;     // a word: written data, an operand, an answer
    localparam STRB_WIDTH = DATA_WIDTH / 8;
    localparam SIZE_WIDTH = 3;      // AXI's AxSIZE: 1 << size bytes

    // The mesh, NocMesh's coordinates (y grows north): PE p at node (p % MESH_X, p / MESH_X),
    // the mesh's local port p.
    localparam MESH_X = 2;
    localparam MESH_Y = 2;
    localparam N_PES  = MESH_X * MESH_Y;

    // The shared memory: node (1, 2), on the north edge link of PE (1, 1), the mesh's top
    // row; XY routes (X first) take every PE's requests to it through (1, 1).
    localparam logic [X_WIDTH-1:0] MEM_X = 2'd1;
    localparam logic [Y_WIDTH-1:0] MEM_Y = 2'd2;

    /* verilator lint_on UNUSEDPARAM */

    // Opcodes, a list per network, 3 bits each (they may change while Mig6 is a prototype).
    typedef enum logic [2:0] {
        REQ_READ   = 3'd0,  // read size bytes at addr; answer DATA
        REQ_WRITE  = 3'd1,  // write the body's data with its strb; no answer
        REQ_ATOMIC = 3'd2,  // the body's atop with its operand at addr; answer DATA, the old word
        REQ_CBO    = 3'd3,  // the cmo on the line of addr; no answer
        REQ_LR     = 3'd4,  // read as a READ, reserve the word of addr for src; answer DATA
        REQ_SC     = 3'd5   // write as a WRITE while src's reservation holds; answer ACK
    } req_op_e;

    typedef enum logic [2:0] {
        RSP_DATA = 3'd0,    // the word of a READ or an LR, the old word of an ATOMIC
        RSP_ACK  = 3'd1     // a write's: data is its status (an SC's: SC_SUCCESS, SC_FAIL)
    } rsp_op_e;

    // The status of an SC in its ACK: RISC-V's SC result, what the core writes to rd.
    localparam logic [DATA_WIDTH-1:0] SC_SUCCESS = DATA_WIDTH'(0);
    localparam logic [DATA_WIDTH-1:0] SC_FAIL    = DATA_WIDTH'(1);

    // A request's head, the first flit: the route to the shared memory, then req_rest_t.
    typedef struct packed {
        req_op_e               op;
        logic [X_WIDTH-1:0]    src_x;   // the requester: where the answer goes
        logic [Y_WIDTH-1:0]    src_y;
        logic [SIZE_WIDTH-1:0] size;    // 1 << size bytes
        logic [ADDR_WIDTH-1:0] addr;    // byte address
        CachePkg::cmo_t        cmo;     // CMO_NONE, or a CBO's operation
    } req_rest_t;

    localparam REQ_DATA_WIDTH = X_WIDTH + Y_WIDTH + $bits(req_rest_t);  // 48

    typedef `DC_NOC_HEAD_T(X_WIDTH, Y_WIDTH, REQ_DATA_WIDTH) req_head_t;  // rest: req_rest_t

    // The bodies, the second flit: a WRITE's and an ATOMIC's.
    typedef struct packed {
        logic [REQ_DATA_WIDTH-DATA_WIDTH-STRB_WIDTH-1:0] zero;
        logic [DATA_WIDTH-1:0]                           data;
        logic [STRB_WIDTH-1:0]                           strb;
    } req_write_t;

    typedef struct packed {
        logic [REQ_DATA_WIDTH-DATA_WIDTH-$bits(AtomicPkg::atop_t)-1:0] zero;
        logic [DATA_WIDTH-1:0]                                         operand;
        AtomicPkg::atop_t                                              atop;
    } req_atomic_t;

    // An answer, one flit: the route back to the request's src_x, src_y, then rsp_rest_t.
    typedef struct packed {
        rsp_op_e               op;
        logic [DATA_WIDTH-1:0] data;    // DATA: the word; ACK: the status
    } rsp_rest_t;

    localparam RSP_DATA_WIDTH = X_WIDTH + Y_WIDTH + $bits(rsp_rest_t);  // 39

    typedef `DC_NOC_HEAD_T(X_WIDTH, Y_WIDTH, RSP_DATA_WIDTH) rsp_t;       // rest: rsp_rest_t

    // The flits and links of the two networks, by the library's macros.
    typedef `DC_NOC_FLIT_T(VC_WIDTH, REQ_DATA_WIDTH)     req_flit_t;
    typedef `DC_NOC_LINK_FWD_T(VC_WIDTH, REQ_DATA_WIDTH) req_link_fwd_t;
    typedef `DC_NOC_FLIT_T(VC_WIDTH, RSP_DATA_WIDTH)     rsp_flit_t;
    typedef `DC_NOC_LINK_FWD_T(VC_WIDTH, RSP_DATA_WIDTH) rsp_link_fwd_t;
    typedef `DC_NOC_LINK_BWD_T(VC_WIDTH)                 link_bwd_t;   // both networks

    // A request with a body (WRITE, SC, ATOMIC) is two flits, the others one.
    function automatic logic req_has_body(req_op_e op);
        return op == REQ_WRITE || op == REQ_SC || op == REQ_ATOMIC;
    endfunction

    // A request that gets an answer: all but a WRITE and a CBO.
    function automatic logic req_answered(req_op_e op);
        return op != REQ_WRITE && op != REQ_CBO;
    endfunction

endpackage
