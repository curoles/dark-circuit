/* Register file with RD_PORTS read ports and WR_PORTS write ports, behavioral.
 *
 * Write: on rising edge, wr_en[p]=1 writes wr_data[p] into register wr_addr[p].
 * When several ports write the same register in the same cycle, the highest port wins.
 * Read is combinational: rd_data[k] is register rd_addr[k] in the same cycle,
 * a register written in this cycle shows new value after the rising edge.
 * Content is unknown until written.
 *
 * Port k is element k of the packed ports, a CPU with 2 read ports connects
 * .rd_addr({rs2, rs1}) and .rd_data({rs2_val, rs1_val}).
 */
module RegFile #(
    parameter  RD_PORTS   = 2,
    parameter  WR_PORTS   = 1,
    parameter  ADDR_WIDTH = 5,                 // 1 << ADDR_WIDTH registers
    parameter  DATA_WIDTH = 32,
    localparam REGS       = 1 << ADDR_WIDTH
)(
    input  wire                                clk,
    input  wire [RD_PORTS-1:0][ADDR_WIDTH-1:0] rd_addr,
    output wire [RD_PORTS-1:0][DATA_WIDTH-1:0] rd_data,
    input  wire [WR_PORTS-1:0]                 wr_en,
    input  wire [WR_PORTS-1:0][ADDR_WIDTH-1:0] wr_addr,
    input  wire [WR_PORTS-1:0][DATA_WIDTH-1:0] wr_data
);
    reg [DATA_WIDTH-1:0] regs [REGS];

    // Higher port writes later in the loop, so it wins.
    always_ff @(posedge clk)
        for (int p = 0; p < WR_PORTS; p++)
            if (wr_en[p])
                regs[wr_addr[p]] <= wr_data[p];

    for (genvar k = 0; k < RD_PORTS; k++) begin : g_rd_port
        assign rd_data[k] = regs[rd_addr[k]];
    end

endmodule
