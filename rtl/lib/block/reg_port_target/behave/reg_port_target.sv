/* Register port target: the device side of the register port (kb pattern
 * rtl/lib/block/plic/register_port). It turns the port's requests and answers into one-clock
 * accesses for a device's registers, and back; the device does no handshake.
 *
 * Port side: a request (req_valid, req_we, req_addr, req_wdata, req_wstrb) is taken when
 * req_valid and req_ready (AGENTS.md valid/ready rules: an offer not taken stays the same);
 * req_ready = !hold. A read is answered exactly one clock after it is taken: rsp_valid with
 * rsp_rdata, from a register, no ready (every answer is taken). A write gets no answer.
 * Device side: in the clock a request is taken, acc_rd (a read) or acc_wr (a write) is 1
 * for that clock, with acc_addr, acc_wdata and acc_wstrb (the request's fields); for a read
 * the device gives the data of acc_addr on rd_data in that same clock, and does a read's
 * side effect then (a PLIC claim): once per read. hold = 1 makes requests wait (the PLIC:
 * the two clocks after a claim); it must come from the device's flops, so that req_ready
 * does, the library's rule for ready.
 *
 *   clock      1        2        3        4        5        6
 *   request    rd A     rd B     wr C     rd D     rd D     -
 *   hold       0        0        0        1        0        0
 *   taken      rd A     rd B     wr C     -        rd D     -
 *   rsp        -        A's data B's data -        -        D's data
 *
 * Reads may follow each other every clock, a read right after a write to the same address
 * sees the written data (the write is done at the edge that takes it).
 *
 *   req_* --> taken? (req_ready = !hold) --> acc_rd/acc_wr, acc_addr/wdata/wstrb --> device
 *   rsp_* <-- register (one clock) <---------------------------- rd_data <--------- device
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module RegPortTarget #(
    parameter  ADDR_WIDTH = 26,             // bits of a byte address inside the device
    parameter  DATA_WIDTH = 32,             // bits of a register access, a multiple of 8
    localparam STRB_WIDTH = DATA_WIDTH / 8
)(
    input  wire                  clk,
    input  wire                  rst_n,     // synchronous reset, active low
    // Register port
    input  wire                  req_valid,
    output wire                  req_ready,
    input  wire                  req_we,    // 1 write, 0 read
    input  wire [ADDR_WIDTH-1:0] req_addr,
    input  wire [DATA_WIDTH-1:0] req_wdata,
    input  wire [STRB_WIDTH-1:0] req_wstrb, // bytes written
    output logic                 rsp_valid, // the answer to a read
    output logic [DATA_WIDTH-1:0] rsp_rdata,
    // Device
    input  wire                  hold,      // take no request now (from the device's flops)
    output wire                  acc_rd,    // a read is taken now
    output wire                  acc_wr,    // a write is taken now
    output wire [ADDR_WIDTH-1:0] acc_addr,
    output wire [DATA_WIDTH-1:0] acc_wdata,
    output wire [STRB_WIDTH-1:0] acc_wstrb,
    input  wire [DATA_WIDTH-1:0] rd_data    // the data of acc_addr, in the clock of acc_rd
);
    `DC_STATIC_ASSERT(a_sizes, ADDR_WIDTH >= 1 && DATA_WIDTH >= 8 && DATA_WIDTH % 8 == 0)

    logic taken;    // a request is taken now

    // @kb: rtl/lib/block/reg_port_target/design
    assign req_ready = !hold;
    assign taken     = req_valid && req_ready;
    assign acc_rd    = taken && !req_we;
    assign acc_wr    = taken && req_we;
    assign acc_addr  = req_addr;
    assign acc_wdata = req_wdata;
    assign acc_wstrb = req_wstrb;

    always_ff @(posedge clk)
        if (!rst_n) rsp_valid <= 1'b0;
        else        rsp_valid <= acc_rd;

    // No reset: the data means nothing while rsp_valid is 0.
    always_ff @(posedge clk)
        if (acc_rd)
            rsp_rdata <= rd_data;

    // Rule 2 of the requester: an offer not taken stays, the same.
    `DC_ASSERT_NEXT(a_req_held, req_valid && !req_ready,
                    req_valid && $stable(req_we) && $stable(req_addr) && $stable(req_wdata) &&
                    $stable(req_wstrb))
    // A read is answered one clock after it is taken, with the data of that clock.
    `DC_ASSERT_NEXT(a_answer_next, acc_rd, rsp_valid && rsp_rdata == $past(rd_data))
    // No answer without a read.
    `DC_ASSERT_NEXT(a_answer_only_read, !acc_rd, !rsp_valid)

endmodule
