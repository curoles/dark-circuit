/* Core Debug Port (CDP).
 *
 * Authors: Igor Lesik 2021
 *
 * Core Debug Port makes the communation channel
 * between JTAG and Core Debug logic.
 *
 * CDP has two interfaces:
 *
 * - JTAG interface and
 * - memory bus interface to Core Debug logic.
 *
 * The debugger uses the JTAG interface to execute instructions JDPACC, CDPACC
 * by going through the TAP state machine, then the instructions take the data
 * and load it into the JDPACC, CDPACC registers, and depending on the data,
 * different registers within the JDP or CDP are accessed, providing the desired
 * comminication to the Core Debug logic.
 *
 * In the **Capture-DR** state, the result of the previous transaction,
 * if any, is returned, together with a 4-bit ACK response.
 *
 * <script type="WaveDrom">
 * { reg: [
 *   {bits: 4, name: 'ACK', attr: ''},
 *   {bits: 32, name: 'DATA', attr: 'Read Result'}
 * ], 
 *   config:{bits: 36}
 * }
 * </script>
 *
 * In the **Shift-DR** state, ACK[3:0] is shifted out first, then 32 bits
 * of "Read Result" data is shifted out.
 * As the returned data is shifted out to `TDO`,
 * new data is shifted in from `TDI`.
 *
 * <script type="WaveDrom">
 * { reg: [
 *   {bits: 4, name: 'DATA', attr: 'Data[3:0]'},
 *   {bits: 32, name: 'DATA', attr: 'Data[35:4]'}
 * ], 
 *   config:{bits: 36}
 * }
 * </script>
 *
 * **Update-DR** operation fulfills the read or write request that is
 * formed by the values that were shifted into the scan chain.
 *
 * <script type="WaveDrom">
 * { reg: [
 *   {bits: 1, name: 'WR', attr: ''},
 *   {bits: 3, name: 'ADDR', attr: 'select'},
 *   {bits: 32, name: 'DATA', attr: 'Data[35:4]'}
 * ], 
 *   config:{bits: 36}
 * }
 * </script>
 */
module CoreDbgPort #(
    parameter MEMI_NR_SLAVES   = 1,
    parameter MEMI_ADDR_WIDTH  = 5,
    parameter MEMI_WDATA_WIDTH = 32,
    parameter MEMI_RDATA_WIDTH = 32
)(
    input  wire tck,        // test clock
    input  wire trst,       // test reset
    input  wire tdi,        // test Data In
    input  wire tms,        // test Mode Select

    input  wire insn_jdpacc_select,     // IR==JDPACC
    input  wire insn_cdpacc_select,     // IR==CDPACC
    input  wire state_test_logic_reset, // TAP_STATE==TEST_LOGIC_REST
    input  wire state_capture_dr,       // TAP_STATE==CAPTURE_DR
    input  wire state_shift_dr,         // TAP_STATE==SHIFT_DR
    input  wire state_update_dr,        // TAP_STATE==UPDATE_DR
    output reg  jdpacc_tdo,             // JDPACC DR output
    output reg  cdpacc_tdo,             // CDPACC DR output

    input  wire                        memi_clk,
    input  wire                        memi_rst,
    output reg  [MEMI_ADDR_WIDTH-1:0]  memi_addr,
    output reg  [MEMI_NR_SLAVES-1:0]   memi_sel, // slave selected & data transfer required
    output reg                         memi_wr_rd, // direction=HIGH? wr:rd
    output reg  [MEMI_WDATA_WIDTH-1:0] memi_wdata,
    input  wire [MEMI_RDATA_WIDTH-1:0] memi_rdata,
    input  wire                        memi_ready
);

    localparam WIDTH = 32+4;

    reg [WIDTH-1:0] jdpacc_reg;
    reg [WIDTH-1:0] cdpacc_reg;

    assign jdpacc_tdo = jdpacc_reg[0];
    assign cdpacc_tdo = cdpacc_reg[0];

    localparam JDPACC_ID = 36'h0;

    always @(posedge tck)
    begin
        if (trst == 1)
            jdpacc_reg <= JDPACC_ID;
        else if (state_test_logic_reset)
            jdpacc_reg <= JDPACC_ID;
        else if (insn_jdpacc_select & state_shift_dr)
            jdpacc_reg <= {tdi, jdpacc_reg[WIDTH-1:1]};
        else if (insn_jdpacc_select & state_capture_dr)
            jdpacc_reg <= jdpacc_capture_dr();
        else if (insn_jdpacc_select & state_update_dr)
            jdpacc_reg <= jdpacc_update_dr(jdpacc_reg);
    end

    function [WIDTH-1:0] jdpacc_capture_dr();
        jdpacc_capture_dr = 'h0;
    endfunction

    function [WIDTH-1:0] jdpacc_update_dr(input [WIDTH-1:0] jdpacc);
        jdpacc_update_dr = jdpacc;
    endfunction

    localparam CDP_OP_SELECT = 3'b000,
               CDP_OP_TADDR  = 3'b001,
               CDP_OP_DTR    = 3'b010;

    reg cdp_req, cdp_cmd_wr, cdp_cmd_rd;
    reg [2:0] cdp_cmd_op;
    reg [31:0] cdp_cmd_data;

    always_ff @(posedge tck)
    begin
        if (trst == 1) begin
            cdpacc_reg <= 'h0;
            cdp_req    <= 0;
        end else if (state_test_logic_reset) begin
            cdpacc_reg <= 'h0;
            cdp_req    <= 0;
        end else if (insn_cdpacc_select & state_shift_dr) begin
            //$display("%t CDPACC shift-in %b", $time, {tdi, cdpacc_reg[WIDTH-1:1]});
            cdpacc_reg <= {tdi, cdpacc_reg[WIDTH-1:1]};
            cdp_req    <= 0;
        end else if (insn_cdpacc_select & state_capture_dr) begin
            //$display("%t captured CDPACC=%h", $time, cdpacc_capture_dr());
            cdpacc_reg <= cdpacc_capture_dr();
            cdp_req    <= 0;
        end else if (insn_cdpacc_select & state_update_dr) begin
            // **Update-DR** operation fulfills the read or write request that is
            // formed by the values that were shifted into the scan chain.

            cdpacc_reg   <=  cdpacc_reg;
            cdp_req      <=  (cdpacc_reg[3:1] == CDP_OP_DTR);
            cdp_cmd_wr   <=  cdpacc_reg[0];
            cdp_cmd_rd   <= ~cdpacc_reg[0];
            cdp_cmd_op   <=  cdpacc_reg[3:1];
            cdp_cmd_data <=  cdpacc_reg[35:4];

            $display("%t CDP Update-DR wr=%b op=%b data=%h", $time,
                cdpacc_reg[0], cdpacc_reg[3:1], cdpacc_reg[35:4]);
        end else begin
            cdp_req <= 0;
        end
    end

    // cdp_req synchronized to Memory Interface clock
    reg memi_req;
    reg memi_req_d1; // signals MUST be stable for 2 clocks on APB

    Jtag2MemiSync _jtag2memi_sync(
        .src_clk(tck),      // Source domain slow clock
        .src_rst(trst),     // Source domain reset
        .src_req(cdp_req),  // Source domain signal to be synchronized
        .dst_clk(memi_clk), // Destination domain fast clock
        .dst_rst(memi_rst), // Destination domain reset
        .dst_req(memi_req)  // Destination domain signal that follows src_req
    );



    reg [31:0] cdpacc_result;
    reg [ 3:0] cdpacc_ack;

    // In the **Capture-DR** state, the result of the previous transaction,
    // if any, is returned, together with a 4-bit ACK response.
    //
    function [WIDTH-1:0] cdpacc_capture_dr();
        cdpacc_capture_dr = {cdpacc_result, cdpacc_ack};
    endfunction


    reg [31:0] cdp_dr_select, cdp_dr_taddr, cdp_dr_dtr;

    always @(posedge tck)
    begin
        if (cdp_cmd_wr) begin
            case (cdp_cmd_op)
                CDP_OP_SELECT: cdp_dr_select <= cdp_cmd_data;
                CDP_OP_TADDR:  cdp_dr_taddr  <= cdp_cmd_data;
                CDP_OP_DTR:    cdp_dr_dtr    <= cdp_cmd_data;
                default: begin end
            endcase
            case (cdp_cmd_op)
                CDP_OP_SELECT: $display("CDP select core %d", cdp_cmd_data);
                CDP_OP_TADDR:  $display("CDP select addr %h", cdp_cmd_data);
                CDP_OP_DTR:    $display("CDP write DTR %h", cdp_cmd_data);
            endcase
        end
    end

    reg memi_wait_rd_reply;

    // APB transaction starts when one-hot bit of `memi_sel` is HIGH.
    //
    always_ff @(posedge memi_clk)
    begin
        if (memi_rst) begin
            memi_sel <= 'h0;
            memi_req_d1 <= 0;
        end else if (memi_req) begin
            $display("%t MEMI REQ WR/RD=%b addr=%h data=%h",
                $time, cdp_cmd_wr, cdp_dr_taddr, cdp_dr_dtr);
            memi_sel    <= 1;// FIXME TODO decode cdp_dr_select;
            memi_addr   <= cdp_dr_taddr;
            memi_wdata  <= cdp_dr_dtr;
            memi_wr_rd  <= cdp_cmd_wr;
            memi_req_d1 <= 1;
        end else if (memi_req_d1) begin
            memi_req_d1 <= 0;
            memi_sel    <= memi_sel;
            memi_addr   <= memi_addr;
            memi_wdata  <= memi_wdata;
            memi_wr_rd  <= memi_wr_rd;
        end else begin
            memi_sel    <= memi_wait_rd_reply & ~memi_ready;
            memi_addr   <= 'h0;
            memi_wdata  <= 'h0;
            memi_wr_rd  <= 0;
            memi_req_d1 <= 0;
        end
    end


    always_ff @(posedge memi_clk)
    begin
        if (memi_rst) begin
            memi_wait_rd_reply <= 0;
        end else begin
            if (memi_wait_rd_reply) begin
                memi_wait_rd_reply <= ~memi_ready;
                if (memi_ready) begin
                    $display("%t CDP: APB read reply %h", $time, memi_rdata);
                    cdpacc_result <= memi_rdata; // TODO fast-slow clock sync?
                    cdpacc_ack <= 4'b0000;
                end else begin
                    $display("%t CDP: waiting for APB ready HIGH", $time);
                end
            end else begin
                memi_wait_rd_reply <= memi_sel & ~memi_wr_rd;
                if (memi_sel & ~memi_wr_rd)
                    $display("%t CDP: Enter wait-rd-reply state", $time);
            end
        end
    end


endmodule: CoreDbgPort
