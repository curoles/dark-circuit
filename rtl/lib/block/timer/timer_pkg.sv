/* The register map of Timer: the timer part of SiFive's CLINT (the RISC-V ACLINT MTIMER), so
 * that software which knows the CLINT finds mtime and mtimecmp where it expects them.
 *
 *   0x0000  msip[h]: 4 bytes per hart, software interrupts (not in Timer: reads 0)
 *   0x4000  mtimecmp[h]: 8 bytes per hart, the low word, then the high word
 *   0xbff8  mtime: the low word, then the high word
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package TimerPkg;

    /* verilator lint_off UNUSEDPARAM */
    localparam int ADDR_BITS     = 16;          // the map is 64 KiB
    localparam int MSIP_BASE     = 'h0000;      // + 4 * hart (reserved in Timer)
    localparam int MTIMECMP_BASE = 'h4000;      // + 8 * hart: low word; high word + 4
    localparam int MTIME         = 'hbff8;      // low word; high word + 4
    localparam int MAX_HARTS     = (MTIME - MTIMECMP_BASE) / 8;     // mtimecmp below mtime
    /* verilator lint_on UNUSEDPARAM */

endpackage
