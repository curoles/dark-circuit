/* Program for TbMig1Mem, linked with sw/riscv/mig1.ld.
 *
 * Known RV32I instructions at 0x00..0x10 and data word 0x12345678 in .rodata,
 * which the linker script places right after the code, at 0x14.
 */
    .section .text.start, "ax"
    .globl _start
_start:
    addi  x1, x0, 5
    addi  x2, x0, 7
    add   x3, x1, x2
    sw    x3, 0x40(x0)
    ecall

    .section .rodata
    .word 0x12345678
