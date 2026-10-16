/* Program counter, made of parts and gates.
 *
 * Author: Igor Lesik 2020
 *
 * Assumes RISC style fixed instruction size of INSN_SIZE bytes. pc is instruction
 * address: bits ADDR_WIDTH-1..ADDR_START of byte address.
 *
 * On rising edge: jump=1 loads jump_addr, else en=1 advances to next instruction,
 * else pc holds (stall). jump wins over en=0, so jump works while stalled.
 * pc wraps around from the top address to 0. pc is unknown until the first jump.
 *
 * Reset is a jump: the core connects .jump(rst | branch_taken) and
 * .jump_addr(rst ? rst_addr : branch_target); pc is rst_addr in the first cycle
 * after the last rising edge with rst=1.
 *
 * Adder with carry in 1 increments pc, Mux2 chooses pc or pc+1 by en,
 * then Mux2 closer to Dff chooses jump_addr by jump, so jump wins.
 */
module PrgCounter #(
    parameter  ADDR_WIDTH = 32,                 // byte address width
    parameter  INSN_SIZE  = 4,                  // bytes in instruction: 1, 2, 4, 8, ...
    localparam ADDR_START = $clog2(INSN_SIZE)   // instruction address starts at this bit of byte address
)(
    input  wire                           clk,
    input  wire                           en,         // 1 advances to next instruction, 0 holds
    input  wire                           jump,       // loads jump_addr, also when en is 0
    input  wire [ADDR_WIDTH-1:ADDR_START] jump_addr,
    output wire [ADDR_WIDTH-1:ADDR_START] pc
);
    localparam W = ADDR_WIDTH - ADDR_START;

    wire [W-1:0] pc_inc, pc_en, pc_next;
    // pc wraps around, carry out is not needed.
    /* verilator lint_off UNUSEDSIGNAL */
    wire         co;
    /* verilator lint_on UNUSEDSIGNAL */

    //TODO switch to Incr
    RippleCarryAdder #(.WIDTH(W)) u_ripple_carry_adder(
        .in1(pc), .in2({W{1'b0}}), .ci(1'b1), .co(co), .sum(pc_inc));

    Mux2 #(W) u_mux2_en  (.in0(pc),    .in1(pc_inc),    .sel(en),   .out(pc_en));
    Mux2 #(W) u_mux2_jump(.in0(pc_en), .in1(jump_addr), .sel(jump), .out(pc_next));
    Dff  #(W) u_dff      (.clk(clk), .in(pc_next), .out(pc));

endmodule
