/* FIFO for small depths, made of blocks, parts and gates.
 *
 * Author: Igor Lesik 2020
 *
 * Entries are flops, so use it for small depths; deep FIFOs need SRAM.
 * First-word fall-through: data_out is the oldest entry while empty is 0,
 * read=1 removes it on rising edge. write=1 adds data_in on rising edge.
 * Write is ignored when full and read is ignored when empty, also when the other
 * happens in the same cycle, so all status outputs depend only on the pointers.
 * Read and write in the same cycle both happen when not full and not empty.
 * almost_full is count >= ALMOST_FULL, almost_empty is count <= ALMOST_EMPTY;
 * defaults mean one entry from full and one entry from empty.
 * rst_n=0 on rising edge empties the FIFO, entries are not cleared.
 *
 * Entries are RegFile with 1 read and 1 write port; its read is combinational,
 * which is what first-word fall-through needs. Pointers are Counters of
 * ADDR_WIDTH+1 bits: low bits address the entry, top bit is wrap bit that flips
 * every time the pointer wraps around. Pointers are equal: empty. Low bits are
 * equal and wrap bits differ: writer is one lap ahead, full.
 * count = wr_ptr - rd_ptr = wr_ptr + ~rd_ptr + 1; count >= N is carry out of
 * count + ~N + 1, count <= N is carry out of N + ~count + 1.
 */
module Fifo #(
    parameter  ADDR_WIDTH   = 3,                     // 1 << ADDR_WIDTH entries
    parameter  DATA_WIDTH   = 8,
    parameter  ALMOST_FULL  = (1 << ADDR_WIDTH) - 1,
    parameter  ALMOST_EMPTY = 1,
    // Not used here, full comes from wrap bits; kept so both versions have the same parameters.
    /* verilator lint_off UNUSEDPARAM */
    localparam DEPTH        = 1 << ADDR_WIDTH
    /* verilator lint_on UNUSEDPARAM */
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  wire                  write,         // ignored when full
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire                  read,          // ignored when empty
    output wire [DATA_WIDTH-1:0] data_out,      // oldest entry, valid when empty is 0
    output wire                  empty,
    output wire                  full,
    output wire [ADDR_WIDTH:0]   count,         // 0..DEPTH entries
    output wire                  almost_full,
    output wire                  almost_empty
);
    localparam PW = ADDR_WIDTH + 1;  // pointer width

    wire [PW-1:0] wr_ptr, rd_ptr, not_rd_ptr, not_count;
    wire          do_write, do_read, not_full, not_empty;
    wire          low_eq, wrap_diff, wrap_eq;
    // Pointers wrap around, carry outs and sums of threshold compares are not needed.
    /* verilator lint_off UNUSEDSIGNAL */
    wire          wr_co, rd_co, count_co;
    wire [PW-1:0] almost_full_diff, almost_empty_diff;
    /* verilator lint_on UNUSEDSIGNAL */

    Inv  #(1) u_inv_full  (.in(full),  .out(not_full));
    Inv  #(1) u_inv_empty (.in(empty), .out(not_empty));
    And2 #(1) u_and2_write(.in1(write), .in2(not_full),  .out(do_write));
    And2 #(1) u_and2_read (.in1(read),  .in2(not_empty), .out(do_read));

    Counter #(.WIDTH(PW)) u_counter_wr(.clk(clk), .rst_n(rst_n), .load(1'b0), .in({PW{1'b0}}),
        .up_down(1'b1), .count_en(do_write), .out(wr_ptr), .co(wr_co));
    Counter #(.WIDTH(PW)) u_counter_rd(.clk(clk), .rst_n(rst_n), .load(1'b0), .in({PW{1'b0}}),
        .up_down(1'b1), .count_en(do_read),  .out(rd_ptr), .co(rd_co));

    RegFile #(.RD_PORTS(1), .WR_PORTS(1), .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_reg_file(
        .clk(clk), .rd_addr(rd_ptr[ADDR_WIDTH-1:0]), .rd_data(data_out),
        .wr_en(do_write), .wr_addr(wr_ptr[ADDR_WIDTH-1:0]), .wr_data(data_in));

    // Empty and full.
    CmpEq #(ADDR_WIDTH) u_cmp_eq_low(.in1(wr_ptr[ADDR_WIDTH-1:0]), .in2(rd_ptr[ADDR_WIDTH-1:0]), .eq(low_eq));
    Xor2  #(1) u_xor2_wrap (.in1(wr_ptr[ADDR_WIDTH]), .in2(rd_ptr[ADDR_WIDTH]), .out(wrap_diff));
    Inv   #(1) u_inv_wrap  (.in(wrap_diff), .out(wrap_eq));
    And2  #(1) u_and2_empty(.in1(low_eq), .in2(wrap_eq),   .out(empty));
    And2  #(1) u_and2_full (.in1(low_eq), .in2(wrap_diff), .out(full));

    // count = wr_ptr - rd_ptr.
    Inv #(PW) u_inv_rd_ptr(.in(rd_ptr), .out(not_rd_ptr));
    RippleCarryAdder #(.WIDTH(PW)) u_ripple_carry_adder_count(
        .in1(wr_ptr), .in2(not_rd_ptr), .ci(1'b1), .co(count_co), .sum(count));

    // Thresholds: carry out of a - b is 1 when a >= b.
    Inv #(PW) u_inv_count(.in(count), .out(not_count));
    RippleCarryAdder #(.WIDTH(PW)) u_ripple_carry_adder_almost_full(
        .in1(count), .in2(~PW'(ALMOST_FULL)), .ci(1'b1), .co(almost_full), .sum(almost_full_diff));
    RippleCarryAdder #(.WIDTH(PW)) u_ripple_carry_adder_almost_empty(
        .in1(PW'(ALMOST_EMPTY)), .in2(not_count), .ci(1'b1), .co(almost_empty), .sum(almost_empty_diff));

endmodule
