/* Register port target: the device side of the register port; made of gates.
 *
 * Same ports and behavior as the behave version (see there). req_ready is ~hold (Inv), an
 * And2 makes taken, two more split it: acc_wr = taken & req_we, acc_rd = taken & ~req_we.
 * The answer: a DffSyncRst for rsp_valid, a DffEn for rsp_rdata (no reset: it means nothing
 * while rsp_valid is 0).
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
    output wire                  rsp_valid, // the answer to a read
    output wire [DATA_WIDTH-1:0] rsp_rdata,
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

    wire taken;     // a request is taken now
    wire we_n;

    // @kb: rtl/lib/block/reg_port_target/design
    Inv  #(1) u_inv_hold(.in(hold), .out(req_ready));
    And2 #(1) u_and2_taken(.in1(req_valid), .in2(req_ready), .out(taken));
    Inv  #(1) u_inv_we(.in(req_we), .out(we_n));
    And2 #(1) u_and2_rd(.in1(taken), .in2(we_n), .out(acc_rd));
    And2 #(1) u_and2_wr(.in1(taken), .in2(req_we), .out(acc_wr));
    assign acc_addr  = req_addr;
    assign acc_wdata = req_wdata;
    assign acc_wstrb = req_wstrb;

    DffSyncRst #(.WIDTH(1), .RST_VAL(1'b0)) u_dff_sync_rst_rsp_valid(
        .clk, .rst_n, .in(acc_rd), .out(rsp_valid));
    DffEn #(.WIDTH(DATA_WIDTH)) u_dff_en_rsp_rdata(
        .clk, .en(acc_rd), .in(rd_data), .out(rsp_rdata));

    // Rule 2 of the requester: an offer not taken stays, the same.
    `DC_ASSERT_NEXT(a_req_held, req_valid && !req_ready,
                    req_valid && $stable(req_we) && $stable(req_addr) && $stable(req_wdata) &&
                    $stable(req_wstrb))
    // A read is answered one clock after it is taken, with the data of that clock.
    `DC_ASSERT_NEXT(a_answer_next, acc_rd, rsp_valid && rsp_rdata == $past(rd_data))
    // No answer without a read.
    `DC_ASSERT_NEXT(a_answer_only_read, !acc_rd, !rsp_valid)

endmodule
