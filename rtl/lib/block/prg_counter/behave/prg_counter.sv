/* Program counter, behavioral.
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
 * @author    Igor Lesik
 * @copyright 2020 Igor Lesik, MIT License
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
    output reg  [ADDR_WIDTH-1:ADDR_START] pc
);

    always_ff @(posedge clk)
        if (jump)
            pc <= jump_addr;
        else if (en)
            pc <= pc + 1'b1;

endmodule
