/* UART: the frame format and the bit timing shared by the serial engine (UartTx, UartRx) and
 * the devices built on it (the register front ends).
 *
 * The frame (asynchronous serial, the line idle at 1): a start bit 0, 5 to 8 data bits, least
 * significant first, a parity bit or none, 1 or 2 stop bits 1. data_bits is coded as a
 * 16550's LCR codes it (WLS: 5 + data_bits bits), so a 16550 front end wires it straight;
 * parity as the simulation models (SimUartTx, SimUartRx) take it. A bit lasts OVERSAMPLE
 * ticks; the tick comes from a TickGen in the device (OVERSAMPLE times the bit rate).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package UartPkg;

    typedef logic [1:0] data_bits_t;    // 5 + data_bits data bits (a 16550's WLS)

    typedef enum logic [1:0] {
        PARITY_NONE = 2'd0,
        PARITY_EVEN = 2'd1,             // the data and parity bits have an even number of ones
        PARITY_ODD  = 2'd2
    } parity_e;

    /* verilator lint_off UNUSEDPARAM */
    localparam int OVERSAMPLE = 16;     // ticks of a bit
    localparam int FRAME_MAX  = 12;     // bits of the longest frame: 1 + 8 + 1 + 2
    /* verilator lint_on UNUSEDPARAM */

endpackage
