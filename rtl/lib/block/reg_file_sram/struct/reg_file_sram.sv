/* Register file with RD_PORTS read ports and 1 write port, made of Sram1R1W blocks.
 *
 * Write: on rising edge, wr_en=1 writes wr_data into register wr_addr.
 * Read is synchronous: on rising edge, rd_en[k]=1 reads register rd_addr[k] into rd_data[k],
 * data comes 1 cycle after address; rd_data[k] holds while rd_en[k]=0.
 * Read and write of the same register in the same cycle reads old data (read-first).
 * Content is unknown until written.
 *
 * Read port k is element k of the packed ports, a CPU with 2 read ports connects
 * .rd_addr({rs2, rs1}) and .rd_data({rs2_val, rs1_val}).
 *
 * Every read port has its own Sram1R1W copy, all copies get the same write,
 * so they always hold the same registers. Memory size is RD_PORTS times
 * the size of the register file.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module RegFileSram #(
    parameter  RD_PORTS   = 2,
    parameter  ADDR_WIDTH = 5,                 // 1 << ADDR_WIDTH registers
    parameter  DATA_WIDTH = 32
)(
    input  wire                                clk,
    input  wire [RD_PORTS-1:0]                 rd_en,
    input  wire [RD_PORTS-1:0][ADDR_WIDTH-1:0] rd_addr,
    output wire [RD_PORTS-1:0][DATA_WIDTH-1:0] rd_data,
    input  wire                                wr_en,
    input  wire [ADDR_WIDTH-1:0]               wr_addr,
    input  wire [DATA_WIDTH-1:0]               wr_data
);
    // One Sram1R1W copy per read port, all written together.
    for (genvar k = 0; k < RD_PORTS; k++) begin : g_rd_port
        Sram1R1W #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_sram_1r1w(
            .clk(clk),
            .rd_en(rd_en[k]), .rd_addr(rd_addr[k]), .data_out(rd_data[k]),
            .wr_en(wr_en), .wr_addr(wr_addr), .data_in(wr_data));
    end

endmodule
