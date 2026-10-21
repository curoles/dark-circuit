/* Register file with RD_PORTS read ports and WR_PORTS write ports, made of blocks and gates.
 *
 * Write: on rising edge, wr_en[p]=1 writes wr_data[p] into register wr_addr[p].
 * When several ports write the same register in the same cycle, the highest port wins.
 * Read is combinational: rd_data[k] is register rd_addr[k] in the same cycle,
 * a register written in this cycle shows new value after the rising edge.
 * Content is unknown until written.
 *
 * Port k is element k of the packed ports, a CPU with 2 read ports connects
 * .rd_addr({rs2, rs1}) and .rd_data({rs2_val, rs1_val}).
 *
 * Decoders make one-hot word lines from addresses. Every register is Dff with a chain
 * of Mux2 in front, one per write port: Mux2 of port p passes wr_data[p] when its word
 * line is 1, otherwise the value from before it; the chain starts with the register
 * itself, so it holds when no port writes it. Higher port is closer to Dff, so it wins.
 * Read port k selects register by AND of every data bit column with its word lines,
 * then OR of the column.
 *
 * Why not GatedClk per register instead of hold Mux2: ASIC synthesis tools insert
 * clock gating cells by themselves where a Mux2 feeds a flop back to itself, and
 * FPGA tools map that Mux2 to the clock enable pin of the flop. Clock gating made
 * of FPGA logic adds clock skew and glitches. So hold Mux2 gives clock gating on ASIC
 * and works on FPGA, explicit GatedClk would give nothing on ASIC and hurt on FPGA.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
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
    wire [WR_PORTS-1:0][REGS-1:0]   wr_wordline;  // wr_wordline[p][r]: port p writes register r
    wire [RD_PORTS-1:0][REGS-1:0]   rd_wordline;  // rd_wordline[k][r]: port k reads register r
    wire [REGS-1:0][DATA_WIDTH-1:0] regs;

    // Write word lines; Decoder en makes them all 0 when port does not write.
    for (genvar p = 0; p < WR_PORTS; p++) begin : g_wr_port
        Decoder #(.SIZE(ADDR_WIDTH)) u_decoder(.in(wr_addr[p]), .en(wr_en[p]), .out(wr_wordline[p]));
    end

    // Registers: Mux2 chain of write ports, then Dff.
    for (genvar r = 0; r < REGS; r++) begin : g_reg
        wire [WR_PORTS:0][DATA_WIDTH-1:0] next;  // next[p+1] is output of Mux2 of port p
        assign next[0] = regs[r];
        for (genvar p = 0; p < WR_PORTS; p++) begin : g_wr_port
            Mux2 #(DATA_WIDTH) u_mux2(.in0(next[p]), .in1(wr_data[p]), .sel(wr_wordline[p][r]),
                                      .out(next[p+1]));
        end
        Dff #(DATA_WIDTH) u_dff(.clk(clk), .in(next[WR_PORTS]), .out(regs[r]));
    end

    // Read ports: for every data bit, AND bit column with read word lines, then OR.
    for (genvar k = 0; k < RD_PORTS; k++) begin : g_rd_port
        Decoder #(.SIZE(ADDR_WIDTH)) u_decoder(.in(rd_addr[k]), .en(1'b1), .out(rd_wordline[k]));
        for (genvar b = 0; b < DATA_WIDTH; b++) begin : g_bit
            wire [REGS-1:0] column, selected;
            for (genvar r = 0; r < REGS; r++) begin : g_column
                assign column[r] = regs[r][b];
            end
            And2     #(REGS) u_and2     (.in1(column), .in2(rd_wordline[k]), .out(selected));
            OrReduce #(REGS) u_or_reduce(.in(selected), .out(rd_data[k][b]));
        end
    end

endmodule
