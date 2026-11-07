/* Atomic unit: atomic memory operations in front of a memory, behavioral (kb
 * rtl/lib/block/atomic/design).
 *
 * Between a requester (the memory side of caches, an arbiter) and a memory, on the library's
 * request channel: requests on valid/ready, a read answered by rsp_valid one or more clocks
 * after the memory took it, in order (no ready), a write without an answer. A request with
 * req_atop == ATOP_NONE (AtomicPkg) passes straight to the memory, its answer straight back.
 * An atomic one (an AtomicLoad or AtomicSwap) is a word of ATOM_WIDTH bits at its aligned
 * address (req_size of ATOM_WIDTH, the operand in that word's lane of req_wdata): the unit
 * takes it into its registers, reads the word from the memory (READ), passes the memory's
 * answer on as the answer (the old word: WAIT), writes op(old, operand) (WRITE) and is idle
 * again; Alu2 does the operation (CLR is ANDN, SET is OR, the min and max of Zbb), a swap
 * writes the operand. Nothing else is taken meanwhile, so the operation is atomic for every
 * requester behind the unit. An atomic request is taken only when no read that passed is
 * waiting for its answer, so the answers stay in order (pending counts them).
 *
 *   req ---> ATOP_NONE: straight on --------------------------------------> mem_req
 *        \-> atomic: registers --> READ --> WAIT (answer: old) --> WRITE --> mem_req
 *   rsp <------------------------------------------------------------------ mem_rsp
 *                                       old --> Alu2 (op, operand) --> new
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module AtomicUnit import AtomicPkg::*; #(
    parameter  ADDR_WIDTH    = 32,                  // byte address
    parameter  DATA_WIDTH    = 64,                  // a beat (a line): ATOM_WIDTH * 2**n
    parameter  ATOM_WIDTH    = 32,                  // bits of an atomic operation's word
    parameter  PENDING_WIDTH = 2,                   // up to 1 << PENDING_WIDTH reads in the memory
    localparam STRB_WIDTH    = DATA_WIDTH / 8
)(
    input  wire                  clk,
    input  wire                  rst_n,             // synchronous reset, active low

    // Requester side
    input  wire                  req_valid,
    output wire                  req_ready,
    input  wire                  req_we,            // 1 write, 0 read (atomic: 0)
    input  wire [ADDR_WIDTH-1:0] req_addr,
    input  wire [2:0]            req_size,          // 1 << req_size bytes
    input  atop_t                req_atop,          // ATOP_NONE, or the atomic operation
    input  wire [DATA_WIDTH-1:0] req_wdata,         // write data, an atomic's operand
    input  wire [STRB_WIDTH-1:0] req_wstrb,
    output wire                  rsp_valid,         // the answer to a read (atomic: old)
    output wire [DATA_WIDTH-1:0] rsp_data,

    // Memory side
    output wire                  mem_req_valid,
    input  wire                  mem_req_ready,
    output wire                  mem_req_we,
    output wire [ADDR_WIDTH-1:0] mem_req_addr,
    output wire [2:0]            mem_req_size,
    output wire [DATA_WIDTH-1:0] mem_req_wdata,
    output wire [STRB_WIDTH-1:0] mem_req_wstrb,
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data
);
    localparam LANES       = DATA_WIDTH / ATOM_WIDTH;   // words of ATOM_WIDTH in a beat
    localparam LANE_BITS   = (LANES > 1) ? $clog2(LANES) : 1;
    localparam ATOM_BYTES  = ATOM_WIDTH / 8;
    localparam ATOM_OFFSET = $clog2(ATOM_BYTES);        // size of an atomic word

    `DC_STATIC_ASSERT(a_widths, ATOM_WIDTH >= 8 && ATOM_WIDTH % 8 == 0 &&
                      DATA_WIDTH % ATOM_WIDTH == 0 && (LANES & (LANES - 1)) == 0)

    typedef enum logic [1:0] {
        IDLE,       // requests pass; an atomic one is taken into the registers
        READ,       // the atomic's read is offered to the memory
        WAIT,       // its answer has not come
        WRITE       // the new word is offered to the memory
    } state_e;

    state_e                 state;
    logic [ADDR_WIDTH-1:0]  addr_q;     // the atomic request
    atop_t                  atop_q;
    logic [ATOM_WIDTH-1:0]  operand_q;
    logic [ATOM_WIDTH-1:0]  new_q;      // op(old, operand), written in WRITE
    logic [PENDING_WIDTH:0] pending;    // reads that passed, not answered
    logic                   atomic;     // the request is atomic
    logic                   take_atomic;
    logic                   pass_read;  // a read passes to the memory now
    logic [LANE_BITS-1:0]   lane;       // the atomic's word in the beat
    logic [STRB_WIDTH-1:0]  lane_strb;  // its bytes
    logic [ATOM_WIDTH-1:0]  old_word;   // its old value, in the memory's answer
    logic [ATOM_WIDTH-1:0]  alu_out;
    logic [ATOM_WIDTH-1:0]  new_word;

    // The atop's operation in Alu2: AXI5's order ADD, CLR, EOR, SET, SMAX, SMIN, UMAX, UMIN
    // (bits [2:0]; the kind is checked elsewhere).
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic Alu2Pkg::op_e alu_op_of(input atop_t a);
    /* verilator lint_on UNUSEDSIGNAL */
        case (a[2:0])
            3'd0:    return Alu2Pkg::ALU2_ADD;
            3'd1:    return Alu2Pkg::ALU2_ANDN;
            3'd2:    return Alu2Pkg::ALU2_XOR;
            3'd3:    return Alu2Pkg::ALU2_OR;
            3'd4:    return Alu2Pkg::ALU2_MAX;
            3'd5:    return Alu2Pkg::ALU2_MIN;
            3'd6:    return Alu2Pkg::ALU2_MAXU;
            default: return Alu2Pkg::ALU2_MINU;
        endcase
    endfunction

    // The word of lane l in a beat.
    function automatic logic [ATOM_WIDTH-1:0] word_of(input logic [DATA_WIDTH-1:0] beat,
                                                      input logic [LANE_BITS-1:0] l);
        return beat[ATOM_WIDTH * l +: ATOM_WIDTH];
    endfunction

    // @kb: rtl/lib/block/atomic/design
    assign atomic      = is_atomic(req_atop);
    assign take_atomic = state == IDLE && req_valid && atomic && pending == '0;
    assign req_ready   = state == IDLE && (atomic ? pending == '0 : mem_req_ready);
    assign pass_read   = state == IDLE && req_valid && !atomic && !req_we && mem_req_ready;

    // The memory sees the requests that pass, else the atomic's read and write.
    assign mem_req_valid = (state == IDLE && req_valid && !atomic) || state == READ ||
                           state == WRITE;
    assign mem_req_we    = (state == IDLE) ? req_we : state == WRITE;
    assign mem_req_addr  = (state == IDLE) ? req_addr : addr_q;
    assign mem_req_size  = (state == IDLE) ? req_size : 3'(ATOM_OFFSET);
    assign mem_req_wdata = (state == IDLE) ? req_wdata : {LANES{new_q}};
    assign mem_req_wstrb = (state == IDLE) ? req_wstrb : lane_strb;
    assign lane_strb     = STRB_WIDTH'({ATOM_BYTES{1'b1}}) << (ATOM_BYTES * lane);

    // Every answer passes; in WAIT it is the atomic's, the old word.
    assign rsp_valid = mem_rsp_valid;
    assign rsp_data  = mem_rsp_data;

    if (LANES > 1) begin: g_lanes
        assign lane = addr_q[ATOM_OFFSET +: LANE_BITS];
    end else begin: g_one_lane
        assign lane = '0;
    end
    assign old_word = word_of(mem_rsp_data, lane);

    Alu2 #(.WIDTH(ATOM_WIDTH)) u_alu2(
        .ctrl(Alu2Pkg::ctrl_of(alu_op_of(atop_q))), .a(old_word), .b(operand_q), .out(alu_out));
    assign new_word = (atop_q == ATOP_SWAP) ? operand_q : alu_out;

    always_ff @(posedge clk)
        if (!rst_n)
            state <= IDLE;
        else
            case (state)
                IDLE:    if (take_atomic)   state <= READ;
                READ:    if (mem_req_ready) state <= WAIT;
                WAIT:    if (mem_rsp_valid) state <= WRITE;
                default: if (mem_req_ready) state <= IDLE;
            endcase

    always_ff @(posedge clk)
        if (take_atomic) begin
            addr_q    <= req_addr;
            atop_q    <= req_atop;
            operand_q <= word_of(req_wdata, (LANES > 1) ? LANE_BITS'(req_addr >> ATOM_OFFSET)
                                                         : '0);
        end

    always_ff @(posedge clk)
        if (state == WAIT && mem_rsp_valid)
            new_q <= new_word;

    // Reads that passed and wait for their answers (in WAIT the answer is the atomic's).
    always_ff @(posedge clk)
        if (!rst_n)
            pending <= '0;
        else if (pass_read && !(mem_rsp_valid && state != WAIT))
            pending <= pending + 1'b1;
        else if (!pass_read && mem_rsp_valid && state != WAIT)
            pending <= pending - 1'b1;

    // An atomic request is a word of ATOM_WIDTH at its aligned address, one of the
    // operations of AtomicPkg (no AtomicStore or AtomicCompare yet), a read.
    `DC_ASSERT(a_atomic_word, !(req_valid && atomic) ||
        (int'(req_size) == ATOM_OFFSET && !req_we &&
         (req_addr & ADDR_WIDTH'(ATOM_BYTES - 1)) == '0 &&
         (req_atop[5:4] == 2'b10 || req_atop == ATOP_SWAP) && req_atop[3] == 1'b0))
    // An answer comes only for a read that passed or the atomic's read.
    `DC_ASSERT(a_answer_expected, !mem_rsp_valid || pending != '0 || state == WAIT)
    `DC_ASSERT(a_pending_no_overflow, !(pass_read && pending == '1))

endmodule
