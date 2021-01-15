
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
    wire                       core_dbg_req;   // Debug request
    wire                       core_dbg_wr_rd; // Debug register write/read request
    wire [APB_ADDR_WIDTH-1:0]  core_dbg_addr;  // Debug register address
    wire [APB_WDATA_WIDTH-1:0] core_dbg_wdata; // Debug register write data

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
        .rdata(apb_rdata),
        .core_dbg_req,
        .core_dbg_wr_rd,
        .core_dbg_addr,
        .core_dbg_wdata
    );

    always_comb begin
        if (apb_sel) $display("%t Core APB select", $time);
    end

    always @(posedge clk)
    begin
        if (core_dbg_req) begin
            if (core_dbg_wr_rd)
                $display("%t Core Debug write addr=%h val=%h", $time, core_dbg_addr, core_dbg_wdata);
            else
                $display("%t Core Debug read addr=%h", $time, core_dbg_addr);
        end
    end

endmodule: TestCore



module TbTop (

);
    localparam NR_CORES = 1;
    localparam APB_ADDR_WIDTH = 5;
    localparam APB_WDATA_WIDTH = 32;
    localparam APB_RDATA_WIDTH = 32;

    JtagBfm _jtag_bfm();

    ApbBfm#(
        .ADDR_WIDTH(APB_ADDR_WIDTH),
        .WDATA_WIDTH(APB_WDATA_WIDTH),
        .RDATA_WIDTH(APB_RDATA_WIDTH),
        .NR_SLAVES(NR_CORES)
    )  _apb_bfm();


    wire clk, rst, rst_n;

    assign clk = _apb_bfm.clk;
    assign rst = ~_apb_bfm.rst_n;
    assign rst_n = _apb_bfm.rst_n;

    wire apb_slave_ready;

    DbgAccPort#(
        .MEMI_NR_SLAVES(NR_CORES),
        .MEMI_ADDR_WIDTH(APB_ADDR_WIDTH),
        .MEMI_WDATA_WIDTH(APB_WDATA_WIDTH)
    ) _dap(
        .tck (_jtag_bfm.tck),
        .trst(_jtag_bfm.trst),
        .tdi (_jtag_bfm.tdi),
        .tms (_jtag_bfm.tms),
        .tdo (_jtag_bfm.tdo),
        .memi_clk(clk),
        .memi_rst(rst),
        .memi_addr (_apb_bfm.addr),
        .memi_sel  (_apb_bfm.sel),
        .memi_wr_rd(_apb_bfm.wr_rd),
        .memi_wdata(_apb_bfm.wdata)
    );

    reg [APB_RDATA_WIDTH-1:0] core_apb_data_out[NR_CORES];

    TestCore#(
        .APB_ADDR_WIDTH(APB_ADDR_WIDTH),
        .APB_WDATA_WIDTH(APB_WDATA_WIDTH),
        .APB_RDATA_WIDTH(APB_RDATA_WIDTH)
    ) _core(
        .clk(clk),
        .rst_n(rst_n),
        .apb_addr  (_apb_bfm.addr),
        .apb_sel   (_apb_bfm.sel),
        .apb_enable(_apb_bfm.enable),
        .apb_wr_rd (_apb_bfm.wr_rd),
        .apb_wdata (_apb_bfm.wdata),
        .apb_ready (apb_slave_ready),
        .apb_rdata (core_apb_data_out[0])
    );

    DbgApbBus#(
        .ADDR_WIDTH(APB_ADDR_WIDTH),
        .WDATA_WIDTH(APB_WDATA_WIDTH),
        .RDATA_WIDTH(APB_RDATA_WIDTH),
        .NR_SLAVES(NR_CORES)
    ) _apb_bus(
        .clk(clk),
        .rst_n(rst_n),
        .addr(_apb_bfm.addr),
        .sel(_apb_bfm.sel),       // slave is selected and data transfer is required
        .enable(_apb_bfm.enable),  // indicates the second+ cycles of an APB transfer
        .wr_rd(_apb_bfm.wr_rd),   // direction=HIGH? wr:rd
        .wdata(_apb_bfm.wdata),   // driven by Bridge when wr_rd=HIGH
        .wstrobe(4'b1111),    // which byte lanes to update during a write transfer wdata[(8n + 7):(8n)]
        .ready(_apb_bfm.ready), // slave uses this signal to extend an APB transfer
        .rdata(_apb_bfm.rdata),
        .s2m_ready(apb_slave_ready),
        .s2m_data(core_apb_data_out)
    );

    initial begin
        uvm_config_db #(virtual JtagBfm)::set(null, "*", "_jtag_bfm", _jtag_bfm);
        uvm_config_db #(virtual  ApbBfm)::set(null, "*", "_apb_bfm", _apb_bfm);
        run_test();
    end

endmodule: TbTop
