/* Atomic unit: atomic memory operations in front of a memory; made of blocks and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there).
 *   state         one-hot {write, wait_rsp, read, idle}, DffSyncRst (reset: idle)
 *   atomic        = OrReduce(req_atop[5:4])            pend_zero = NorReduce(pending)
 *   take_atomic   = idle AND req_valid AND atomic AND pend_zero
 *   req_ready     = idle AND Mux2(mem_req_ready, pend_zero, atomic)
 *   pass_read     = idle AND req_valid AND ~atomic AND ~req_we AND mem_req_ready
 *   mem_req_*     = Mux2(the atomic's registers or new word, the request's, idle);
 *                   valid = (idle AND req_valid AND ~atomic) OR read OR write
 *   pending       = Counter: up on pass_read, down on an answer outside wait_rsp
 *   addr, atop, operand: DffEn on take_atomic (operand: MuxN of the request's lanes)
 *   old word      = MuxN of the answer's lanes by the atomic's lane; Alu2's controls a MuxN
 *                   of the eight ctrl_of constants by atop[2:0]; new word Mux2(Alu2,
 *                   operand, CmpEq(atop, ATOP_SWAP)), DffEn in wait_rsp on the answer
 *   lane strobes  = Decoder of the lane, each bit for ATOM_BYTES bytes
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
    localparam CTRL_WIDTH  = $bits(Alu2Pkg::ctrl_t);

    `DC_STATIC_ASSERT(a_widths, ATOM_WIDTH >= 8 && ATOM_WIDTH % 8 == 0 &&
                      DATA_WIDTH % ATOM_WIDTH == 0 && (LANES & (LANES - 1)) == 0)

    wire                   idle, read, wait_rsp, write;    // the state, one-hot
    wire [3:0]             state, state_next;
    wire                   atomic;      // the request is atomic
    wire                   atomic_n;
    wire                   we_n;
    wire                   pend_zero;   // no read that passed waits for its answer
    wire                   take_atomic;
    wire                   pass_req;    // an ordinary request is offered: it passes
    wire                   pass_read;   // a read passes to the memory now
    wire                   ready_sel;
    wire                   ready_n, rsp_n;
    wire                   take_n;
    wire                   wait_n;
    wire                   read_taken;  // the memory takes the atomic's read
    wire                   write_taken; // ... its write
    wire                   rsp_other;   // an answer of a read that passed
    wire                   count_en;
    wire                   answer;      // the atomic's answer comes (wait_rsp)
    wire [PENDING_WIDTH:0] pending;     // reads that passed, not answered
    wire                   is_swap;
    wire [ADDR_WIDTH-1:0]  addr_q;      // the atomic request
    atop_t                 atop_q;
    wire [ATOM_WIDTH-1:0]  operand;     // its operand, in its lane of the request
    wire [ATOM_WIDTH-1:0]  operand_q;
    wire [ATOM_WIDTH-1:0]  old_word;    // the old word, in its lane of the answer
    wire [ATOM_WIDTH-1:0]  alu_out;
    wire [ATOM_WIDTH-1:0]  new_word;
    wire [ATOM_WIDTH-1:0]  new_q;
    wire [STRB_WIDTH-1:0]  lane_strb;   // the atomic word's bytes
    Alu2Pkg::ctrl_t        ctrl;        // Alu2's controls for atop_q
    // Not needed: the counter never passes its range.
    /* verilator lint_off UNUSEDSIGNAL */
    wire                   count_co;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/atomic/design
    OrReduce  #(2) u_or_reduce_atomic(.in(req_atop[5:4]), .out(atomic));
    Inv       #(1) u_inv_atomic(.in(atomic), .out(atomic_n));
    Inv       #(1) u_inv_we    (.in(req_we), .out(we_n));
    NorReduce #(PENDING_WIDTH + 1) u_nor_reduce_pend(.in(pending), .out(pend_zero));
    AndReduce #(4) u_and_reduce_take(.in({idle, req_valid, atomic, pend_zero}), .out(take_atomic));
    And3      #(1) u_and3_pass_req(.in1(idle), .in2(req_valid), .in3(atomic_n), .out(pass_req));
    AndReduce #(3) u_and_reduce_pass_read(.in({pass_req, we_n, mem_req_ready}), .out(pass_read));
    Mux2      #(1) u_mux2_ready(.in0(mem_req_ready), .in1(pend_zero), .sel(atomic),
                                .out(ready_sel));
    And2      #(1) u_and2_ready(.in1(idle), .in2(ready_sel), .out(req_ready));

    // The state: idle -> read (an atomic taken) -> wait_rsp (its read taken) -> write (its
    // answer) -> idle (its write taken).
    Inv  #(1) u_inv_ready(.in(mem_req_ready), .out(ready_n));
    Inv  #(1) u_inv_rsp  (.in(mem_rsp_valid), .out(rsp_n));
    Inv  #(1) u_inv_take (.in(take_atomic), .out(take_n));
    And2 #(1) u_and2_read_taken (.in1(read), .in2(mem_req_ready), .out(read_taken));
    And2 #(1) u_and2_write_taken(.in1(write), .in2(mem_req_ready), .out(write_taken));
    Ao21 #(1) u_ao21_idle (.in1(idle), .in2(take_n), .in3(write_taken), .out(state_next[0]));
    Ao21 #(1) u_ao21_read (.in1(read), .in2(ready_n), .in3(take_atomic), .out(state_next[1]));
    Ao21 #(1) u_ao21_wait (.in1(wait_rsp), .in2(rsp_n), .in3(read_taken), .out(state_next[2]));
    Ao21 #(1) u_ao21_write(.in1(write), .in2(ready_n), .in3(answer), .out(state_next[3]));
    DffSyncRst #(.WIDTH(4), .RST_VAL(4'b0001)) u_dff_sync_rst_state(
        .clk, .rst_n, .in(state_next), .out(state));
    assign {write, wait_rsp, read, idle} = state;
    And2 #(1) u_and2_answer(.in1(wait_rsp), .in2(mem_rsp_valid), .out(answer));

    // The memory sees the requests that pass, else the atomic's read and write.
    Or3  #(1) u_or3_mem_valid(.in1(pass_req), .in2(read), .in3(write), .out(mem_req_valid));
    Mux2 #(1)          u_mux2_we  (.in0(write), .in1(req_we), .sel(idle), .out(mem_req_we));
    Mux2 #(ADDR_WIDTH) u_mux2_addr(.in0(addr_q), .in1(req_addr), .sel(idle), .out(mem_req_addr));
    Mux2 #(3)          u_mux2_size(.in0(3'(ATOM_OFFSET)), .in1(req_size), .sel(idle),
                                   .out(mem_req_size));
    Mux2 #(DATA_WIDTH) u_mux2_wdata(.in0({LANES{new_q}}), .in1(req_wdata), .sel(idle),
                                    .out(mem_req_wdata));
    Mux2 #(STRB_WIDTH) u_mux2_wstrb(.in0(lane_strb), .in1(req_wstrb), .sel(idle),
                                    .out(mem_req_wstrb));

    // Every answer passes; in wait_rsp it is the atomic's, the old word.
    assign rsp_valid = mem_rsp_valid;
    assign rsp_data  = mem_rsp_data;

    // Reads that passed and wait for their answers.
    Inv     #(1) u_inv_wait(.in(wait_rsp), .out(wait_n));
    And2    #(1) u_and2_rsp_other(.in1(mem_rsp_valid), .in2(wait_n), .out(rsp_other));
    Xor2    #(1) u_xor2_count_en (.in1(pass_read), .in2(rsp_other), .out(count_en));
    Counter #(.WIDTH(PENDING_WIDTH + 1)) u_counter_pending(
        .clk, .rst_n, .load(1'b0), .in({(PENDING_WIDTH + 1){1'b0}}), .up_down(pass_read),
        .count_en, .out(pending), .co(count_co));

    // The lanes: the operand of the request, the old word of the answer, the write's bytes.
    if (LANES > 1) begin: g_lanes
        wire [LANES-1:0] lane_one;   // the atomic's lane, one-hot
        MuxN #(.N(LANES), .WIDTH(ATOM_WIDTH)) u_mux_n_operand(
            .in(req_wdata), .sel(req_addr[ATOM_OFFSET +: LANE_BITS]), .out(operand));
        MuxN #(.N(LANES), .WIDTH(ATOM_WIDTH)) u_mux_n_old(
            .in(mem_rsp_data), .sel(addr_q[ATOM_OFFSET +: LANE_BITS]), .out(old_word));
        Decoder #(.SIZE(LANE_BITS)) u_decoder_lane(
            .in(addr_q[ATOM_OFFSET +: LANE_BITS]), .en(1'b1), .out(lane_one));
        for (genvar l = 0; l < LANES; l++) begin: g_lane
            assign lane_strb[ATOM_BYTES * l +: ATOM_BYTES] = {ATOM_BYTES{lane_one[l]}};
        end
    end else begin: g_one_lane
        assign operand   = req_wdata;
        assign old_word  = mem_rsp_data;
        assign lane_strb = '1;
    end

    // The atomic request, kept; the new word.
    DffEn #(ADDR_WIDTH + 6 + ATOM_WIDTH) u_dff_en_atomic(
        .clk, .en(take_atomic), .in({req_addr, req_atop, operand}),
        .out({addr_q, atop_q, operand_q}));
    MuxN #(.N(8), .WIDTH(CTRL_WIDTH)) u_mux_n_ctrl(
        .in({Alu2Pkg::ctrl_of(Alu2Pkg::ALU2_MINU), Alu2Pkg::ctrl_of(Alu2Pkg::ALU2_MAXU),
             Alu2Pkg::ctrl_of(Alu2Pkg::ALU2_MIN),  Alu2Pkg::ctrl_of(Alu2Pkg::ALU2_MAX),
             Alu2Pkg::ctrl_of(Alu2Pkg::ALU2_OR),   Alu2Pkg::ctrl_of(Alu2Pkg::ALU2_XOR),
             Alu2Pkg::ctrl_of(Alu2Pkg::ALU2_ANDN), Alu2Pkg::ctrl_of(Alu2Pkg::ALU2_ADD)}),
        .sel(atop_q[2:0]), .out(ctrl));
    Alu2 #(.WIDTH(ATOM_WIDTH)) u_alu2(.ctrl, .a(old_word), .b(operand_q), .out(alu_out));
    CmpEq #(6) u_cmp_eq_swap(.in1(atop_q), .in2(AtomicPkg::ATOP_SWAP), .eq(is_swap));
    Mux2 #(ATOM_WIDTH) u_mux2_new(.in0(alu_out), .in1(operand_q), .sel(is_swap),
                                  .out(new_word));
    DffEn #(ATOM_WIDTH) u_dff_en_new(.clk, .en(answer), .in(new_word), .out(new_q));

    // See the behave version.
    `DC_ASSERT(a_atomic_word, !(req_valid && atomic) ||
        (int'(req_size) == ATOM_OFFSET && !req_we &&
         (req_addr & ADDR_WIDTH'(ATOM_BYTES - 1)) == '0 &&
         (req_atop[5:4] == 2'b10 || req_atop == ATOP_SWAP) && req_atop[3] == 1'b0))
    `DC_ASSERT(a_answer_expected, !mem_rsp_valid || !pend_zero || wait_rsp)
    `DC_ASSERT(a_pending_no_overflow, !(pass_read && pending == '1))
    `DC_ASSERT(a_one_hot_state, $onehot(state))

endmodule
