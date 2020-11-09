/* Mig1 Core.
 *
 * Author: Igor Lesik 2020
 * Copyright: Igor Lesik 2020
 *
 */
module Mig1Core #(
    parameter   ADDR_WIDTH,
    localparam  INSN_SIZE  = 4, // Mig1 word size is 32 bits
    localparam  DATA_SIZE  = INSN_SIZE, // insn and data bus is 4 bytes
    localparam  DATA_WIDTH = DATA_SIZE * 8
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire [ADDR_WIDTH-1:2] rst_addr,
    output reg                   insn_fetch_en,
    output reg  [ADDR_WIDTH-1:2] insn_fetch_addr
);

    PrgCounter#(.ADDR_WIDTH(ADDR_WIDTH), .INSN_SIZE(INSN_SIZE))
        pc_(
            .clk(clk),
            .rst(rst),
            .rst_addr(rst_addr),
            .pc_addr(insn_fetch_addr)
    );

    //always @ (posedge clk)
    //begin
    //    if (rst) begin
    //        insn_fetch_addr <= rst_addr;
    //        insn_fetch_en <= 0;
    //    else begin
    //        //
    //    end
    //end

endmodule: Mig1CPU

