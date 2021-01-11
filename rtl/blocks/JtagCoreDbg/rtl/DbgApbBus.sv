/* APB bus.
 *
 * Author: Igor Lesik 2020
 *
 * The Advanced Peripheral Bus (APB) is used for connecting
 * low bandwidth peripherals.
 * It is a simple non-pipelined protocol that can be used to read/write
 * from a master to a number of slaves through the shared bus.
 * The reads and writes shares the same set of signals
 * and no burst data transfers are supported.
 * APB is a simple interface that could be used to provide
 * access to the programmable control registers of peripheral devices.
 *
 * Unpipelined protocol means that a second transfer
 * cannot start before the first transfer completes.
 * Every transfer takes at least two cycles.
 *
 * ```
 *              Master/APB Bridge
 *                 ^
 *                 |
 *                 v
 *   bus ------------------------------
 *           ^         ^          ^
 *           |         |          |
 *           v         v          v
 *        slave1    slave2     slave3
 * ```
 *
 * Programming the control registers of internal CPU devices,
 * for example, Debug Logic control registers can be implemented
 * with JTAG TAP connected to APB.
 *
 * ```
 *   TDI ----->| R/W | Address | DATA |-----> TDO
 *                |       |       |
 *                |       |       +--->
 *                |       +-----------> APB transaction
 *                +------------------->
 * ```
 *
 * The APB protocol has two independent data buses, one for read data and one for write data.
 * Because the buses do not have their own individual handshake signals,
 * it is not possible for data transfers to occur on both buses at the same time.
 *
 * Verilog module ApbBus takes inputs from APB Bridge and outputs Slave
 * signals to APB Bridge.
 */
module DbgApbBus #(
    parameter ADDR_WIDTH=32,
    parameter WDATA_WIDTH=32,
    parameter RDATA_WIDTH=32,
    parameter NR_SLAVES=1
)(
    input wire                 clk, // rising edge of `clk` times all transfers on the APB
    input wire                 rst_n,

    // Signals driven by APB bridge
    input wire [ADDR_WIDTH-1:0]  addr,
    input wire [NR_SLAVES-1:0]   sel,     // slave is selected and data transfer is required
    output reg                   enable,  // indicates the second+ cycles of an APB transfer
    input wire                   wr_rd,   // direction=HIGH? wr:rd
    input wire [WDATA_WIDTH-1:0] wdata,   // driven by Bridge when wr_rd=HIGH
    input wire [3:0]             wstrobe, // which byte lanes to update during a write transfer wdata[(8n + 7):(8n)]

    // Signals driven by current Slave
    output reg                   ready, // slave uses this signal to extend an APB transfer
    output reg [RDATA_WIDTH-1:0] rdata,
    // not implemented slave_err

    // Signals driven by Slaves
    input wire [NR_SLAVES-1:0]   s2m_ready,
    input wire [RDATA_WIDTH-1:0] s2m_data[NR_SLAVES]
);
    genvar i;

    // ====================================================================
    // Mux all s2m signals based on currently selected Slave using OR gates.
    // ====================================================================

    wire [NR_SLAVES-1:0]   sel_s2m_ready; // AND2(sel[n], ~s2m_ready[n])
    wire [RDATA_WIDTH-1:0] sel_s2m_data[NR_SLAVES];

    generate
        for (i = 0; i < NR_SLAVES; i = i + 1) begin
            assign sel_s2m_ready[i] = sel[i] & ~s2m_ready[i];
            assign sel_s2m_data[i] = {NR_SLAVES{sel[i]}} & s2m_data[i];
        end
    endgenerate

    wire ready_n;
    assign ready_n = |sel_s2m_ready;
    assign ready = ~ready;

    always_comb
    begin
        rdata = {RDATA_WIDTH{1'b0}};
        for (int unsigned slave_id = 0; slave_id < NR_SLAVES; slave_id++)
        begin
            rdata |= sel_s2m_data[slave_id];
        end
    end
 
    // =========================
    // APB bus state transitions
    // =========================

    wire transfer_required;
    assign transfer_required = |sel; // start transfer if some Slave is selected

    reg [1:0] state;
    localparam [1:0] IDLE=0, SETUP=1, ACCESS=2, ILLEGAL_STATE=3;

    always @(posedge clk)
    begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            case (state)
            IDLE: begin
                state <= transfer_required? SETUP:IDLE;
            end
            SETUP: begin
                // The bus only remains in the SETUP state for one clock cycle
                // and always moves to the ACCESS state on the next
                // rising edge of the clock.
                state <= ACCESS;
            end
            ACCESS: begin
                // Exit from the ACCESS state is controlled by the READY signal from the slave:
                // - If READY is held LOW by the slave then the peripheral bus remains in
                //   the ACCESS state.
                // - If READY is driven HIGH by the slave then the ACCESS state is exited
                //   and the bus returns to the IDLE state if no more transfers are required.
                // Alternatively, the bus moves directly to the SETUP state if another transfer follows.
                state <= ready? (transfer_required? SETUP:IDLE) : ACCESS;
            end
            ILLEGAL_STATE: begin
                state <= IDLE;
            end
            endcase
        end
    end

    // The enable signal, ENABLE, is asserted in the ACCESS state.
    assign enable = (state == ACCESS);



endmodule: DbgApbBus
