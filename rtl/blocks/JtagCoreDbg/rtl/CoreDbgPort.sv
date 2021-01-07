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
 * - memory bus interface to Core Debug logic..
 */
module CoreDbgPort (
    input  wire tck,        // test clock
    input  wire trst,       // test reset
    input  wire tdi,        // test Data In
    input  wire tms,        // test Mode Select
    output reg  jdpacc_tdo,
    output reg  cdpacc_tdo
);


endmodule: CoreDbgPort
