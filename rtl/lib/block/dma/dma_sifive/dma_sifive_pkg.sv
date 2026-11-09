/* The register map of DmaSifive: SiFive's platform DMA (PDMA, FU540-C000 manual chapter 12;
 * Linux drivers/dma/sf-pdma), so that software which knows it finds every register where it
 * expects it.
 *
 * Per channel c, at c * 0x1000:
 *
 *   0x000  Control     [0] claim, [1] run, [14] doneIE, [15] errorIE, [30] done, [31] error
 *   0x004  NextConfig  [2] repeat, [3] order, [27:24] wsize, [31:28] rsize (WARL: the beat)
 *   0x008  NextBytes        8 bytes: the low word, then the high word
 *   0x010  NextDestination  8 bytes
 *   0x018  NextSource       8 bytes
 *   0x104  ExecConfig       read only: the Next config of the transfer running
 *   0x108  ExecBytes        read only, 8 bytes: bytes left
 *   0x110  ExecDestination  read only, 8 bytes: the current destination
 *   0x118  ExecSource       read only, 8 bytes: the current source
 *
 * doneIE and errorIE are bits 14 and 15 as Linux has them (it runs on FU540 boards); the
 * manual's table says 26 and 27 (kb rtl/lib/block/dma/design). Two interrupts a channel:
 * 2c its done, 2c + 1 its error.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package DmaSifivePkg;

    /* verilator lint_off UNUSEDPARAM */
    localparam int CHAN_BITS    = 12;       // a channel's registers: 4 KiB
    localparam int CONTROL      = 'h000;
    localparam int NEXT_CONFIG  = 'h004;
    localparam int NEXT_BYTES   = 'h008;    // + 4: the high word
    localparam int NEXT_DST     = 'h010;
    localparam int NEXT_SRC     = 'h018;
    localparam int EXEC_CONFIG  = 'h104;
    localparam int EXEC_BYTES   = 'h108;
    localparam int EXEC_DST     = 'h110;
    localparam int EXEC_SRC     = 'h118;
    localparam int CLAIM_BIT    = 0;        // Control
    localparam int RUN_BIT      = 1;
    localparam int DONE_IE_BIT  = 14;
    localparam int ERR_IE_BIT   = 15;
    localparam int DONE_BIT     = 30;
    localparam int ERR_BIT      = 31;
    localparam int REPEAT_BIT   = 2;        // NextConfig, ExecConfig
    localparam int ORDER_BIT    = 3;
    localparam int WSIZE_LSB    = 24;       // 4 bits each: log2 of a transaction's bytes
    localparam int RSIZE_LSB    = 28;
    /* verilator lint_on UNUSEDPARAM */

endpackage
