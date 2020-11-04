
module RegFile #(
    parameter SIZE = 64,
    parameter ADDR_WIDTH = `CLOG(SIZE),
    parameter REG_WIDTH = 64
)(
    input  wire                  clk,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [ADDR_WIDTH-1:0] wr_enable,
    input  wire [REG_WIDTH-1:0]  wr_val,
    output wire [REG_WIDTH-1:0]  val 
);

wire gclk;
GatedClk gclk_(.clk(clk), .enable(wr_enable), .scan_enable(1'b0), .gclk(gclk));

wire [REG_WIDTH-1:0] r [SIZE];
Dff ff_ [SIZE] #(.WIDTH(REG_WIDTH)) (.clk(gclk), .in(wr_val), .out(r));

/*genvar i;
generate
    for (i = 0; i <= SIZE; i = i + 1) begin : generate_reg
        Dff ff #(.WIDTH(REG_WIDTH)) (.clk(gclk), .in(wr_val), .out(r[i]));
    end 
endgenerate*/

wire [REG_WIDTH-1:0] s [SIZE/8];

genvar i;
generate
    for (i = 0; i <= (SIZE/8); i = i + 1) begin : generate_s1
        Mux8 s1_ #(.WIDTH(REG_WIDTH)) (.in1(r[i*8+0]),.in2(r[i*8+1]),.in3(r[i*8+2]),.in4(r[i*8+3]),
                                       .in5(r[i*8+4]),.in6(r[i*8+5]),.in7(r[i*8+6]),.in8(r[i*8+7]),
                                       .sel(wr_addr[2:0]),.out(s[i]));
    end
endgenerate

Mux8 s2_ #(.WIDTH(REG_WIDTH)) (.in1(s[0]),.in2(s[1]),.in3(s[2]),.in4(s[3]),
                               .in5(s[4]),.in6(s[5]),.in7(s[6]),.in8(s[7]),
                               .sel(wr_addr[5:3]),.out(val));

/*function [1:0]  rf_data_write (
    input int unsigned ic_set,
    input int unsigned ic_way,
    input int unsigned cl_word,
    input [OP_MSB:0] data
);
    // verilator public
    mem[ic_set][ic_way][cl_word*OP_SZ +: OP_SZ] = data;
    rf_data_write = {1'b0, 1'b0};
endfunction*/

endmodule: RegFile
