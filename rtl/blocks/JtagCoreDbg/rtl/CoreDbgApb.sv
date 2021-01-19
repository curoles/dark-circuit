/* Core Debug APB bus interface.
 *
 * Authors: Igor Lesik 2020
 *
 * Module CoreDbgApb is APB bus slave.
 *
 *
 *
 */
module CoreDbgApb #(
    parameter APB_ADDR_WIDTH =5,
    parameter APB_WDATA_WIDTH=32,
    parameter APB_RDATA_WIDTH=32
)(
    input wire                 clk, // rising edge of `clk` times all transfers on the APB
    input wire                 rst_n,

    // Signals from APB Master and APB bus
    input wire [APB_ADDR_WIDTH-1:0]  addr,
    input wire                       sel,     // slave is selected and data transfer is required
    input wire                       enable,  // indicates the second+ cycles of an APB transfer
    input wire                       wr_rd,   // direction=HIGH? wr:rd
    input wire [APB_WDATA_WIDTH-1:0] wdata,   // driven by Bridge when wr_rd=HIGH
    input wire [3:0]                 wstrobe, // which byte lanes to update during a write transfer wdata[(8n + 7):(8n)]

    // Signals driven by current Slave
    output reg                   ready, // slave uses this signal to extend an APB transfer, when ready is LOW the transfer extended
    output reg [APB_RDATA_WIDTH-1:0] rdata,
    // not implemented slave_err

    output reg                       core_dbg_req,
    output reg                       core_dbg_wr_rd, // Debug register write/read request
    output reg [APB_ADDR_WIDTH-1:0]  core_dbg_addr,  // Debug register address
    output reg [APB_WDATA_WIDTH-1:0] core_dbg_wdata  // Debug register write data
);

    assign ready = 1; // TODO check later if Dbg Logic may need extended transfers

    reg [1:0] state;
    localparam [1:0] IDLE=0, WRITE=1, READ=2;

    always @(posedge clk)
    begin
        if (!rst_n) begin
            state <= IDLE;
            core_dbg_req <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (sel) $display("%t Core Dbg Apb Slave selected", $time);
                    state <= sel? (wr_rd? WRITE:READ) : IDLE;
                    core_dbg_req <= 0;
                end
                WRITE: begin
                    if (sel && wr_rd) begin // sel and other inputs MUST be stable at least 2 cycles
                        core_dbg_req   <= 1;
                        core_dbg_wr_rd <= 1;
                        core_dbg_addr  <= addr;
                        core_dbg_wdata <= wdata;
                        $display("%t Core Dbg Apb write[%h]=%h", $time, addr, wdata);
                    end
                    state <= IDLE;
                end
                READ: begin
                    if (sel && !wr_rd) begin // sel and other inputs MUST be stable at least 2 cycles
                        core_dbg_req   <= 1;
                        core_dbg_wr_rd <= 0;
                        core_dbg_addr  <= addr;
                        $display("%t Core Dbg Apb read[%h]=", $time, addr);
                        rdata <= 32'h123;
                    end
                    state <= IDLE;
                end
                default: begin
                    state <= IDLE;
                    core_dbg_req <= 0;
                end
            endcase
        end
    end




endmodule: CoreDbgApb
