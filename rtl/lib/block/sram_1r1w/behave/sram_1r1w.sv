/* SRAM with 1 read port and 1 write port, behavioral.
 *
 * Write: on rising edge, wr_en=1 writes data_in into word wr_addr.
 * Read is synchronous: on rising edge, rd_en=1 reads word rd_addr into data_out,
 * data comes 1 cycle after address; data_out holds while rd_en=0.
 * Read and write of the same word in the same cycle reads old data (read-first).
 * Content is unknown until written.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Sram1R1W #(
    parameter  ADDR_WIDTH = 4,
    parameter  DATA_WIDTH = 8,
    localparam WORDS      = 1 << ADDR_WIDTH
)(
    input  wire                  clk,
    input  wire                  rd_en,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] data_in,
    output reg  [DATA_WIDTH-1:0] data_out
);
    reg [DATA_WIDTH-1:0] mem [WORDS];

    always_ff @(posedge clk)
        if (wr_en)
            mem[wr_addr] <= data_in;

    always_ff @(posedge clk)
        if (rd_en)
            data_out <= mem[rd_addr];

endmodule
