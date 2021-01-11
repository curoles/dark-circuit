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
    output reg [APB_RDATA_WIDTH-1:0] rdata
    // not implemented slave_err
);

    assign ready = 1; // TODO check later if Dbg Logic may need extended transfers

    reg [1:0] state;
    localparam [1:0] IDLE=0, WRITE=1, READ=2;

    always @(posedge clk)
    begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    state <= sel? (wr_rd? WRITE:READ) : IDLE;
                end
                WRITE: begin
                    if (sel && wr_rd) begin // sel and other inputs MUST be stable at least 2 cycles
                        // write to Dbg Page using addr and wdata
                    end
                    state <= IDLE;
                end
                READ: begin
                    if (sel && !wr_rd) begin // sel and other inputs MUST be stable at least 2 cycles
                        // read to rdata from Dbg Page using addr
                    end
                    state <= IDLE;
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end




endmodule: CoreDbgApb
