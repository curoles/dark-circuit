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
module DbgAccPort (
    input  wire tck,   // test clock
    input  wire trst,  // test reset
    input  wire tdi,   // test Data In
    input  wire tms,   // test Mode Select
    output reg  tdo    // test Data Out
);

    wire jdpacc_tdo;
    wire cdpacc_tdo;

    wire insn_jdpacc_select;
    wire insn_cdpacc_select;

    JtagTap _jtag_tap(
        .tck(tck),
        .trst(trst),
        .tdi(tdi),
        .tms(tms),
        .tdo(tdo),
        .jdpacc_tdo(jdpacc_tdo),
        .cdpacc_tdo(cdpacc_tdo)
    );

    CoreDbgPort _cdp(
        .tck(tck),
        .trst(trst),
        .tdi(tdi),
        .tms(tms),
        .jdpacc_tdo(jdpacc_tdo),
        .cdpacc_tdo(cdpacc_tdo)
    );

endmodule: DbgAccPort
