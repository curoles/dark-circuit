/* SRAM with 1 read port and 1 write port, made of blocks and gates.
 *
 * Write: on rising edge, wr_en=1 writes data_in into word wr_addr.
 * Read is synchronous: on rising edge, rd_en=1 reads word rd_addr into data_out,
 * data comes 1 cycle after address; data_out holds while rd_en=0.
 * Read and write of the same word in the same cycle reads old data (read-first).
 * Content is unknown until written.
 *
 * Decoders make one-hot word lines from addresses. Every word is Mux2 and Dff:
 * write when its write word line is 1, otherwise hold. Read selects word by
 * AND of every data bit column with read word lines, then OR of the column.
 * Size is WORDS*DATA_WIDTH flops, use it for small memories and for learning.
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
    output wire [DATA_WIDTH-1:0] data_out
);
    wire [WORDS-1:0]            wr_wordline, rd_wordline;
    wire [WORDS*DATA_WIDTH-1:0] words;     // word k is words[k*DATA_WIDTH +: DATA_WIDTH]
    wire [DATA_WIDTH-1:0]       read_val, data_next;

    // One-hot word lines; Decoder en makes them all 0 when port is not enabled.
    Decoder #(.SIZE(ADDR_WIDTH)) u_decoder_wr(.in(wr_addr), .en(wr_en), .out(wr_wordline));
    Decoder #(.SIZE(ADDR_WIDTH)) u_decoder_rd(.in(rd_addr), .en(rd_en), .out(rd_wordline));

    genvar k, b;
    generate
    // Words: write when write word line is 1, otherwise hold.
    for (k = 0; k < WORDS; k = k + 1) begin: g_word
        wire [DATA_WIDTH-1:0] next;
        Mux2 #(DATA_WIDTH) u_mux2(.in0(words[k*DATA_WIDTH +: DATA_WIDTH]), .in1(data_in),
                                  .sel(wr_wordline[k]), .out(next));
        Dff  #(DATA_WIDTH) u_dff (.clk(clk), .in(next), .out(words[k*DATA_WIDTH +: DATA_WIDTH]));
    end
    // Read: for every data bit, AND bit column with read word lines, then OR.
    for (b = 0; b < DATA_WIDTH; b = b + 1) begin: g_bit
        wire [WORDS-1:0] column, selected;
        for (k = 0; k < WORDS; k = k + 1) begin: g_column
            assign column[k] = words[k*DATA_WIDTH + b];
        end
        And2     #(WORDS) u_and2     (.in1(column), .in2(rd_wordline), .out(selected));
        OrReduce #(WORDS) u_or_reduce(.in(selected), .out(read_val[b]));
    end
    endgenerate

    // data_out holds while rd_en is 0.
    Mux2 #(DATA_WIDTH) u_mux2_out(.in0(data_out), .in1(read_val), .sel(rd_en), .out(data_next));
    Dff  #(DATA_WIDTH) u_dff_out (.clk(clk), .in(data_next), .out(data_out));

endmodule
