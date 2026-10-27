//TODO take DirectCacheRdOnly and make RW version

module DirectCache #(
    parameter ADDR_WIDTH = 32,
)(
    input wire clk,
    input wire rst_n,
