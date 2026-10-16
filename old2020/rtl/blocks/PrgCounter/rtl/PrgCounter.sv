/* Program Counter.
 *
 * Author: Igor Lesik 2020
 * Copyright: Igor Lesik 2020
 *
 * Assumes RISC style fixed instruction word size.
 */
module PrgCounter #(
    parameter   ADDR_WIDTH = 32,
    parameter   INSN_SIZE  = 4,
    localparam  INSN_WIDTH = INSN_SIZE * 8,
    localparam  ADDR_OFS   = (INSN_SIZE <= 1)? 0 :
                             (INSN_SIZE <= 2)? 1 :
                             (INSN_SIZE <= 4)? 2 :
                             (INSN_SIZE <= 8)? 3 :
                             (INSN_SIZE <=16)? 4 : -1
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire [ADDR_WIDTH-1:ADDR_OFS] rst_addr,
    output reg  [ADDR_WIDTH-1:ADDR_OFS] pc_addr
);

    reg rst_delay1;

    always @ (posedge clk)
    begin
        pc_addr <= next_pc(pc_addr, rst_delay1, rst_addr);
        rst_delay1 <= rst;
    end

    // Calculate next PC.
    //
    function bit [ADDR_WIDTH-1:ADDR_OFS] next_pc(
        input bit [ADDR_WIDTH-1:ADDR_OFS] current_pc,
        input bit rst,
        input bit [ADDR_WIDTH-1:ADDR_OFS] rst_addr
    );
        if (rst) begin
            next_pc = rst_addr;
        end
        else begin
            next_pc = current_pc + 1;
        end

        //$display("PC: %x, rst: %d", next_pc, rst);
    endfunction

endmodule: PrgCounter

