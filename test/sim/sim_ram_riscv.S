/* Program for TbSimRamRiscv.
 *
 * Known RV32I instructions at address 0, and two data words in section .tbdata
 * that the link places at address 0x80, so the hex file has an address jump.
 */
    .section .text
    .globl _start
_start:
    addi  x1, x0, 5
    addi  x2, x0, 7
    add   x3, x1, x2
    sw    x3, 0x40(x0)
    ecall

    .section .tbdata, "a"
    .word 0x12345678
    .word 0xCAFEF00D
