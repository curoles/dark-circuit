/* Program for TbMig2: ends with the semihosting call SYS_EXIT (0x18).
 *
 * On RV32, SYS_EXIT passes only the reason, in a1, and no status: the testbench ends the run
 * with exit 0 for ADP_Stopped_ApplicationExit (0x20026) and exit 1 for any other reason.
 * REASON comes from the build (-DREASON=...). The semihosting test uses SYS_EXIT_EXTENDED.
 */
    .section .text.start, "ax"
    .globl _start
_start:
    li    a0, 0x18                  # SYS_EXIT
    li    a1, REASON
    slli  x0, x0, 0x1f              # semihosting call: entry no-op, EBREAK, exit no-op
    ebreak
    srai  x0, x0, 7
1:
    j     1b                        # not reached: the exit ends the run
