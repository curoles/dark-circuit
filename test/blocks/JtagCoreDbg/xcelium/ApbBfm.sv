interface ApbBfm #(
    parameter ADDR_WIDTH  =  5,
    parameter WDATA_WIDTH = 32,
    parameter RDATA_WIDTH = 32,
    parameter NR_SLAVES   =  1
);

    bit clk;
    bit rst_n;

    bit [ADDR_WIDTH-1:0]  addr;
    bit [NR_SLAVES-1:0]   sel;
    bit                   enable;
    bit                   wr_rd;
    bit [WDATA_WIDTH-1:0] wdata;
    bit [3:0]             wstrobe;

    bit                   ready;
    bit [RDATA_WIDTH-1:0] rdata;

    initial
    begin
        clk = 0;
        forever begin
            #1;
            clk = ~clk;
        end
    end

    initial
    begin
        rst_n = 1;
        #1;
        rst_n = 0;
        #5;
        rst_n = 1;
    end

endinterface: ApbBfm
