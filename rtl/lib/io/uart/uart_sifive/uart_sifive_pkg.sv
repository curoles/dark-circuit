/* The register map of UartSifive: SiFive's UART (FE310, the Freedom platforms), so that
 * software which knows it (drivers, the SiFive BSPs) finds every register where it expects it.
 *
 *   0x00  txdata  [7:0] data (write: into the transmit FIFO), [31] full (read)
 *   0x04  rxdata  [7:0] data (read: out of the receive FIFO), [31] empty
 *   0x08  txctrl  [0] txen, [1] nstop (2 stop bits), [18:16] txcnt (the transmit watermark)
 *   0x0c  rxctrl  [0] rxen, [18:16] rxcnt (the receive watermark)
 *   0x10  ie      [0] txwm, [1] rxwm: the interrupt enables
 *   0x14  ip      [0] txwm, [1] rxwm: pending (read only)
 *   0x18  div     [15:0] the bit rate: f_clk / (div + 1)
 *
 * The frame is 8 data bits, no parity, 1 or 2 stop bits. The FIFOs have 8 entries.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package UartSifivePkg;

    /* verilator lint_off UNUSEDPARAM */
    localparam int ADDR_BITS  = 12;     // the map is 4 KiB
    localparam int TXDATA     = 'h00;
    localparam int RXDATA     = 'h04;
    localparam int TXCTRL     = 'h08;
    localparam int RXCTRL     = 'h0c;
    localparam int IE         = 'h10;
    localparam int IP         = 'h14;
    localparam int DIV        = 'h18;
    localparam int N_REGS     = 7;      // the words from 0x00 to 0x18, every one a register
    localparam int FLAG_BIT   = 31;     // txdata's full, rxdata's empty
    localparam int EN_BIT     = 0;      // txctrl's txen, rxctrl's rxen
    localparam int NSTOP_BIT  = 1;      // txctrl
    localparam int CNT_LSB    = 16;     // txctrl's txcnt, rxctrl's rxcnt
    localparam int CNT_BITS   = 3;
    localparam int TXWM_BIT   = 0;      // ie, ip
    localparam int RXWM_BIT   = 1;
    localparam int DIV_BITS   = 16;
    localparam int FIFO_ADDR  = 3;      // 1 << FIFO_ADDR entries a FIFO
    /* verilator lint_on UNUSEDPARAM */

endpackage
