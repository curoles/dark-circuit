/* Program for TbMig2 fetch test: straight-line instructions, then EBREAK.
 *
 * 5 instructions retire, the core halts at the EBREAK at 0x10.
 */
    .section .text.start, "ax"
    .globl _start
_start:
    addi  x1, x0, 1
    addi  x2, x1, 2
    xor   x3, x1, x2
    lui   x4, 0x12345
    ebreak
