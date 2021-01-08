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
 */
module CoreDbgPort (
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
    output reg  cdpacc_tdo              // CDPACC DR output
);

    localparam WIDTH = 36;

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

    reg cdp_cmd_wr, cdp_cmd_rd;
    reg [2:0] cdp_cmd_op;
    reg [31:0] cdp_cmd_data;

    always @(posedge tck)
    begin
        if (trst == 1)
            cdpacc_reg <= 'h0;
        else if (state_test_logic_reset)
            cdpacc_reg <= 'h0;
        else if (insn_cdpacc_select & state_shift_dr)
            cdpacc_reg <= {tdi, cdpacc_reg[WIDTH-1:1]};
        else if (insn_cdpacc_select & state_capture_dr)
            cdpacc_reg <= cdpacc_capture_dr();
        else if (insn_cdpacc_select & state_update_dr) begin
            // **Update-DR** operation fulfills the read or write request that is
            // formed by the values that were shifted into the scan chain.

            cdpacc_reg   <=  cdpacc_reg;
            cdp_cmd_wr   <=  cdpacc_reg[0];
            cdp_cmd_rd   <= ~cdpacc_reg[0];
            cdp_cmd_op   <=  cdpacc_reg[3:1];
            cdp_cmd_data <=  cdpacc_reg[35:4];
        end
    end

    function [WIDTH-1:0] jdpacc_capture_dr();
        jdpacc_capture_dr = 'h0;
    endfunction

    function [WIDTH-1:0] jdpacc_update_dr(input [WIDTH-1:0] jdpacc);
        jdpacc_update_dr = jdpacc;
    endfunction

    reg [31:0] cdpacc_result;
    reg [ 3:0] cdpacc_ack;

    // In the **Capture-DR** state, the result of the previous transaction,
    // if any, is returned, together with a 4-bit ACK response.
    //
    function [WIDTH-1:0] cdpacc_capture_dr();
        cdpacc_capture_dr = {cdpacc_ack, cdpacc_result};
    endfunction

    localparam CDP_SELECT = 3'b000,
               CDP_TADDR  = 3'b001,
               CDP_DTR    = 3'b010;

    reg [31:0] cdp_dr_select, cdp_dr_taddr, cdp_dr_dtr;

    always @(posedge tck)
    begin
        if (cdp_cmd_wr) begin
            case (cdp_cmd_op)
                CDP_SELECT: cdp_dr_select <= cdp_cmd_data;
                CDP_TADDR:  cdp_dr_taddr  <= cdp_cmd_data;
                CDP_DTR:    cdp_dr_dtr    <= cdp_cmd_data;
                default: begin end
            endcase
        end
    end

endmodule: CoreDbgPort
