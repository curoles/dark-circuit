/* Program for TbMig2 with +expect_trap +first_ebreak_traps +expect_regs: traps, MRET.
 *
 * - mtvec and mepc ignore the low bits that writes give them (direct mode only,
 *   no compressed instructions).
 * - ECALL with MIE=1: in the handler mstatus has MPP=3, MPIE=1, MIE=0 (0x1880),
 *   mcause 11, mepc the ECALL; the handler moves mepc to the next instruction and
 *   returns with MRET, which restores MIE=1, MPIE=1 (0x1888).
 * - minstret does not count the ECALL (a trap), but counts the handler.
 * - WFI is a no-op.
 * - EBREAK traps (the testbench is not yet attached as debugger, +first_ebreak_traps):
 *   mcause 3, mepc and mtval the EBREAK. The handler halts with EBREAK, which now
 *   halts the core.
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    la     t0, handler
    ori    t1, t0, 3
    csrw   mtvec, t1                # mode bits read 0
    csrr   x10, mtvec
    sub    x10, x10, t0
    li     t2, 0x103
    csrw   mepc, t2                 # bits 1:0 read 0
    csrr   x11, mepc

    csrsi  mstatus, 8               # MIE=1
    csrr   x12, mstatus
    rdinstret x20
ecall_insn:
    ecall
    rdinstret x21
    sub    x22, x21, x20
    csrr   x16, mstatus
    wfi
    addi   x17, x0, 1
ebreak_insn:
    ebreak
    ebreak                          # not reached: the handler halts

handler:
    csrr   t3, mcause
    li     t4, 11
    beq    t3, t4, on_ecall
dispatch_end:
    mv     x18, t3                  # breakpoint
    csrr   x19, mtval
    la     t4, ebreak_insn
    sub    x19, x19, t4
    csrr   x23, mepc
    sub    x23, x23, t4
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 10, 0
    EXPECT_REG 11, 0x100
    EXPECT_REG 12, 0x1808           # MPP=3, MIE=1
    EXPECT_REG 13, 0x1880           # in the handler: MPP=3, MPIE=1, MIE=0
    EXPECT_REG 14, 11
    EXPECT_REG 15, 0
    EXPECT_REG 16, 0x1888           # after MRET: MPP=3, MPIE=1, MIE=1
    EXPECT_REG 17, 1
    EXPECT_REG 18, 3
    EXPECT_REG 19, 0
    EXPECT_REG 23, 0
    # rdinstret x20 itself, the handler up to on_ecall, then on_ecall to MRET; not the ECALL.
    EXPECT_REG 22, 1 + (dispatch_end - handler) / 4 + (on_ecall_end - on_ecall) / 4
expect_end:

on_ecall:
    csrr   x13, mstatus
    mv     x14, t3
    csrr   x15, mepc
    la     t4, ecall_insn
    sub    x15, x15, t4
    csrr   t4, mepc
    addi   t4, t4, 4
    csrw   mepc, t4
    mret
on_ecall_end:
