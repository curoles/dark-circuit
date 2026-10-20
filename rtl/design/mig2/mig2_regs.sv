/* Mig2 registers x0..x31: two reads and one write per cycle.
 *
 * Reads are combinational (RegFile), rs1_data and rs2_data are the registers rs1 and
 * rs2 in the same cycle; a write happens on rising edge, so a register written in a
 * cycle reads the new value from the next cycle.
 * x0 is always 0: reads of x0 give 0 and writes to x0 are dropped (RegFile has no
 * reset, so x0 is never stored).
 * While halt=1 the debug port owns read port 0 and the write port: dbg_reg_rdata is
 * register dbg_reg_addr, dbg_reg_wr=1 writes dbg_reg_wdata into it on rising edge.
 * The core is idle then, so pipeline and debug never use the ports together.
 */
module Mig2Regs import Mig2Pkg::*; (
    input  wire                        clk,
    input  wire                        halt,         // 1: debug port owns read port 0 and write port

    // Pipeline. Vector ports are written with their range, see Mig2Pkg about ports.
    input  logic [REG_ADDR_WIDTH-1:0]  rs1,
    input  logic [REG_ADDR_WIDTH-1:0]  rs2,
    output logic [WIDTH-1:0]           rs1_data,
    output logic [WIDTH-1:0]           rs2_data,
    input  wire                        rd_we,
    input  logic [REG_ADDR_WIDTH-1:0]  rd,
    input  logic [WIDTH-1:0]           rd_data,

    // Debug, used while halt=1.
    input  logic [REG_ADDR_WIDTH-1:0]  dbg_reg_addr,
    input  wire                        dbg_reg_wr,
    input  logic [WIDTH-1:0]           dbg_reg_wdata,
    output logic [WIDTH-1:0]           dbg_reg_rdata
);
    // Read port 0 and write port: pipeline, or debug while halted.
    reg_addr_t rd_addr0;
    reg_addr_t wr_addr;
    word_t     wr_data;
    logic      wr_en;
    word_t     rf_data0;   // RegFile read port 0
    word_t     rf_data1;   // RegFile read port 1

    assign rd_addr0 = halt ? dbg_reg_addr  : rs1;
    assign wr_addr  = halt ? dbg_reg_addr  : rd;
    assign wr_data  = halt ? dbg_reg_wdata : rd_data;
    assign wr_en    = (halt ? dbg_reg_wr : rd_we) && wr_addr != '0;  // x0 is never written

    RegFile #(.RD_PORTS(2), .WR_PORTS(1), .ADDR_WIDTH(REG_ADDR_WIDTH), .DATA_WIDTH(WIDTH)) u_reg_file(
        .clk(clk),
        .rd_addr({rs2, rd_addr0}), .rd_data({rf_data1, rf_data0}),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data));

    // x0 reads 0.
    assign rs1_data      = (rd_addr0 == '0) ? '0 : rf_data0;
    assign rs2_data      = (rs2 == '0)      ? '0 : rf_data1;
    assign dbg_reg_rdata = rs1_data;

endmodule
