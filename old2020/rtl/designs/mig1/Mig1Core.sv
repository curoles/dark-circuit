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
    localparam  DATA_WIDTH = DATA_SIZE * 8,
    parameter   DBG_APB_ADDR_WIDTH  = 5,
    parameter   DBG_APB_WDATA_WIDTH = 32,
    parameter   DBG_APB_RDATA_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire [ADDR_WIDTH-1:2] rst_addr,

    // Debug APB signals
    input  wire [DBG_APB_ADDR_WIDTH-1:0]  dbg_apb_addr,
    input  wire                           dbg_apb_sel,     // slave is selected and data transfer is required
    input  wire                           dbg_apb_enable,  // indicates the second+ cycles of an APB transfer
    input  wire                           dbg_apb_wr_rd,   // direction=HIGH? wr:rd
    input  wire [DBG_APB_WDATA_WIDTH-1:0] dbg_apb_wdata,   // driven by Bridge when wr_rd=HIGH
    output reg                            dbg_apb_ready,   // slave uses this signal to extend an APB transfer, when ready is LOW the transfer extended
    output reg  [DBG_APB_RDATA_WIDTH-1:0] dbg_apb_rdata,

    output reg                   insn_fetch_en,
    output reg  [ADDR_WIDTH-1:2] insn_fetch_addr
);
    wire                           dbg_req;   // Debug request
    wire                           dbg_wr_rd; // Debug register write/read request
    wire [DBG_APB_ADDR_WIDTH-1:0]  dbg_addr;  // Debug register address
    wire [DBG_APB_WDATA_WIDTH-1:0] dbg_wdata; // Debug register write data
    reg  [DBG_APB_RDATA_WIDTH-1:0] dbg_rdata;
    reg                            dbg_rd_ready;

    CoreDbgApb#(
        .APB_ADDR_WIDTH(DBG_APB_ADDR_WIDTH),
        .APB_WDATA_WIDTH(DBG_APB_WDATA_WIDTH),
        .APB_RDATA_WIDTH(DBG_APB_RDATA_WIDTH)
    ) _dbg(
        .clk(clk),
        .rst_n(~rst),
        .addr(dbg_apb_addr),
        .sel(dbg_apb_sel),
        .enable(dbg_apb_enable),
        .wr_rd(dbg_apb_wr_rd),
        .wdata(dbg_apb_wdata),
        .wstrobe(4'b1111),
        .ready(dbg_apb_ready),
        .rdata(dbg_apb_rdata),
        .core_dbg_req(dbg_req),
        .core_dbg_wr_rd(dbg_wr_rd),
        .core_dbg_addr(dbg_addr),
        .core_dbg_wdata(dbg_wdata),
        .core_dbg_rdata(dbg_rdata),
        .core_dbg_rd_ready(dbg_rd_ready)
    );

    reg [31:0] dbg_reg[32];

    always @(posedge clk)
    begin
        if (dbg_req) begin
            if (dbg_wr_rd) begin
                $display("%t MIG1: Debug write addr=%h val=%h",
                    $time, dbg_addr, dbg_wdata);
                dbg_reg[integer'(dbg_addr)] <= dbg_wdata;
                dbg_rd_ready <= 0;
            end else begin
                $display("%t MIG1: Debug read addr[%h]=%h",
                    $time, dbg_addr, dbg_reg[integer'(dbg_addr)]);
                dbg_rdata <= dbg_reg[integer'(dbg_addr)];
                dbg_rd_ready <= 1;
            end
        end else begin
            dbg_rd_ready <= 0;
        end
    end

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

endmodule: Mig1Core

