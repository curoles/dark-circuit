/* Debug Access Port (DAP).
 *
 * Authors: Igor Lesik 2021
 *
 * Debug Access Port (DAP) is an implementation of Debug Interface.
 * DAP provides external debugger with a standard interface to access
 * Core debug facilities.
 *
 * DAP contains:
 *
 * - JTAG TAP Controller with TAP FSM.
 * - JTAG Debug Port and Core Debug Port.
 */
module DbgAccPort #(
    parameter MEMI_NR_SLAVES=1,
    parameter MEMI_ADDR_WIDTH=5,
    parameter MEMI_WDATA_WIDTH=32
)(
    input  wire tck,   // test clock
    input  wire trst,  // test reset
    input  wire tdi,   // test Data In
    input  wire tms,   // test Mode Select
    output reg  tdo,   // test Data Out

    input  wire                        memi_clk,
    input  wire                        memi_rst,
    output reg  [MEMI_ADDR_WIDTH-1:0]  memi_addr,
    output reg  [MEMI_NR_SLAVES-1:0]   memi_sel,
    output reg                         memi_wr_rd,
    output reg  [MEMI_WDATA_WIDTH-1:0] memi_wdata
);

    wire jdpacc_tdo;
    wire cdpacc_tdo;

    wire insn_jdpacc_select;
    wire insn_cdpacc_select;

    wire state_test_logic_reset;
    wire state_capture_dr;
    wire state_shift_dr;
    wire state_update_dr;

    JtagTap _jtag_tap(
        .tck(tck),
        .trst(trst),
        .tdi(tdi),
        .tms(tms),
        .tdo(tdo),
        .jdpacc_tdo(jdpacc_tdo),
        .cdpacc_tdo(cdpacc_tdo),
        .state_test_logic_reset,
        .state_capture_dr,
        .state_shift_dr,
        .state_update_dr
    );

    CoreDbgPort _cdp(
        .tck(tck),
        .trst(trst),
        .tdi(tdi),
        .tms(tms),
        .insn_jdpacc_select(insn_jdpacc_select),
        .insn_cdpacc_select(insn_cdpacc_select),
        .state_test_logic_reset,
        .state_capture_dr,
        .state_shift_dr,
        .state_update_dr,
        .jdpacc_tdo(jdpacc_tdo),
        .cdpacc_tdo(cdpacc_tdo),
        .memi_clk,
        .memi_rst,
        .memi_addr,
        .memi_sel,
        .memi_wr_rd,
        .memi_wdata
    );

endmodule: DbgAccPort
