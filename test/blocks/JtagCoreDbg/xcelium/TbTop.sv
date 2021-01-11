
module TestCore #(
    parameter APB_ADDR_WIDTH  = 5,
    parameter APB_WDATA_WIDTH = 32,
    parameter APB_RDATA_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,

    // Signals from APB Master and APB bus
    input wire [APB_ADDR_WIDTH-1:0]  apb_addr,
    input wire                       apb_sel,     // slave is selected and data transfer is required
    input wire                       apb_enable,  // indicates the second+ cycles of an APB transfer
    input wire                       apb_wr_rd,   // direction=HIGH? wr:rd
    input wire [APB_WDATA_WIDTH-1:0] apb_wdata,   // driven by Bridge when wr_rd=HIGH

    // Signals driven by current Slave
    output reg apb_ready, // slave uses this signal to extend an APB transfer, when ready is LOW the transfer extended
    output reg [APB_RDATA_WIDTH-1:0] apb_rdata
);

    CoreDbgApb#(
        .APB_ADDR_WIDTH(APB_ADDR_WIDTH),
        .APB_WDATA_WIDTH(APB_WDATA_WIDTH),
        .APB_RDATA_WIDTH(APB_RDATA_WIDTH)
    ) _dbg(
        .clk(clk),
        .rst_n(rst_n),
        .addr(apb_addr),
        .sel(apb_sel),
        .enable(apb_enable),
        .wr_rd(apb_wr_rd),
        .wdata(apb_wdata),
        .wstrobe(4'b1111),
        .ready(apb_ready),
        .rdata(apb_rdata)
    );

endmodule: TestCore



module TbTop (

);
    wire tck;   // test clock
    wire trst;  // test reset
    wire tdi;   // test Data In
    wire tms;   // test Mode Select
    wire tdo;   // test Data Out

    localparam NR_CORES = 1;
    localparam APB_ADDR_WIDTH = 5;
    localparam APB_WDATA_WIDTH = 32;
    localparam APB_RDATA_WIDTH = 32;

    wire clk, rst;

    wire [APB_ADDR_WIDTH-1:0]  apb_addr;
    wire [NR_CORES-1:0]        apb_sel;
    wire                       apb_wr_rd;
    wire [APB_WDATA_WIDTH-1:0] apb_wdata;
    wire                       apb_enable;
    wire                       apb_ready, apb_slave_ready;

    DbgAccPort#(
        .MEMI_NR_SLAVES(NR_CORES),
        .MEMI_ADDR_WIDTH(APB_ADDR_WIDTH),
        .MEMI_WDATA_WIDTH(APB_WDATA_WIDTH)
    ) _dap(
        .tck(tck),
        .trst(trst),
        .tdi(tdi),
        .tms(tms),
        .tdo(tdo),
        .memi_clk(clk),
        .memi_rst(rst),
        .memi_addr(apb_addr),
        .memi_sel(apb_sel),
        .memi_wr_rd(apb_wr_rd),
        .memi_wdata(apb_wdata)
    );

    reg [APB_RDATA_WIDTH-1:0] core_apb_data_out[NR_CORES];

    TestCore#(
        .APB_ADDR_WIDTH(APB_ADDR_WIDTH),
        .APB_WDATA_WIDTH(APB_WDATA_WIDTH),
        .APB_RDATA_WIDTH(APB_RDATA_WIDTH)
    ) _core(
        .clk(clk),
        .rst_n(~rst),
        .apb_addr(apb_addr),
        .apb_sel(apb_sel),
        .apb_enable(apb_enable),
        .apb_wr_rd(apb_wr_rd),
        .apb_wdata(apb_wdata),
        .apb_ready(apb_slave_ready),
        .apb_rdata(core_apb_data_out[0])
    );

    DbgApbBus#(
        .ADDR_WIDTH(APB_ADDR_WIDTH),
        .WDATA_WIDTH(APB_WDATA_WIDTH),
        .RDATA_WIDTH(APB_RDATA_WIDTH),
        .NR_SLAVES(NR_CORES)
    ) _apb_bus(
        .clk(clk),
        .rst_n(~rst),
        .addr(apb_addr),
        .sel(apb_sel),       // slave is selected and data transfer is required
        .enable(apb_enable),  // indicates the second+ cycles of an APB transfer
        .wr_rd(apb_wr_rd),   // direction=HIGH? wr:rd
        .wdata(apb_wdata),   // driven by Bridge when wr_rd=HIGH
        .wstrobe(4'b1111),    // which byte lanes to update during a write transfer wdata[(8n + 7):(8n)]
        .ready(apb_ready), // slave uses this signal to extend an APB transfer
        .rdata(apb_rdata),
        .s2m_ready(apb_slave_ready),
        .s2m_data(core_apb_data_out)
    );

endmodule: TbTop
