/* Program for TbMig1 with +expect_trap +resumes=1 +expect_regs: JAL in the corners of the
 * pipeline, for the redirect of JAL from ID.
 *
 * - Wrong path: a JAL right after an instruction that redirects (taken branch, JALR,
 *   ECALL, MRET) must not jump and must not write rd (x7 stays 0). Its target is `fail`,
 *   an EBREAK without a register table: reaching it fails the run.
 * - A JAL behind a division waits in ID while the division stalls EX; its target runs
 *   once (x6 counts), its link is right.
 * - A JAL to an address not divisible by 4 traps: misaligned fetch, mtval the target,
 *   mepc the JAL, no rd written; the handler continues after the JAL.
 * - A JAL right after an EBREAK that halts the core is flushed at the halt and runs
 *   after the debugger resumes (the debugger adds 0x100 to a0).
 * - Back-to-back JALs, and the link of a JAL used by the very next instruction (the
 *   first one at the target), through forwarding.
 * Instructions right after a JAL that jumps must be skipped; they set bits in x17.
 * The ECALL handler continues 2 instructions after the ECALL (the wrong-path JAL after
 * it never runs). After the halting EBREAK: number of expected registers, then pairs
 * register, value.
 */
    .option norelax

    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    la    x30, handler
    csrw  mtvec, x30
    addi  x6, x0, 0
    addi  x7, x0, 0
    addi  x17, x0, 0
    addi  x28, x0, 0

    # Wrong path: JALs right after a taken branch, a JALR, an ECALL.
    beq   x0, x0, 1f
    jal   x7, fail
1:
    la    x27, 2f
    jalr  x0, 0(x27)
    jal   x7, fail
2:
    ecall
    jal   x7, fail

    # JAL behind a division.
    li    x8, 100
    li    x9, 7
    div   x26, x8, x9
    jal   x24, div_target
div_link:
    ori   x17, x17, 0x01
div_target:
    addi  x6, x6, 1

    # JAL to a misaligned target: traps.
misaligned_jal:
    jal   x7, misaligned_jal + 6

    # JAL right after an EBREAK that halts the core.
    addi  a0, x0, 5
    ebreak                          # debugger: a0 <- 0x105, resume
    jal   x23, after_halt
halt_link:
    ori   x17, x17, 0x02
after_halt:
    addi  x25, a0, 0

    # Back-to-back JALs.
    jal   x20, b2b
b2b_link1:
    ori   x17, x17, 0x04
b2b:
    jal   x21, b2b_end
b2b_link2:
    ori   x17, x17, 0x08
b2b_end:

    # The link used by the next instruction.
    jal   x18, use_link
link_used:
    ori   x17, x17, 0x10
use_link:
    addi  x19, x18, 0

    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 6, 1
    EXPECT_REG 7, 0
    EXPECT_REG 17, 0
    EXPECT_REG 18, link_used
    EXPECT_REG 19, link_used
    EXPECT_REG 20, b2b_link1
    EXPECT_REG 21, b2b_link2
    EXPECT_REG 23, halt_link
    EXPECT_REG 24, div_link
    EXPECT_REG 25, 0x105
    EXPECT_REG 26, 14
    EXPECT_REG 28, 2                # ECALL and the misaligned JAL
    EXPECT_REG 29, 0                # mtval - target
    EXPECT_REG 30, 0                # mepc - the misaligned JAL
expect_end:

    # Traps: ECALL continues 2 instructions after it, the misaligned JAL right after it.
handler:
    addi  x28, x28, 1
    csrr  x31, mcause
    beqz  x31, on_misaligned
    csrr  x31, mepc
    addi  x31, x31, 8
    csrw  mepc, x31
    mret
    jal   x7, fail                  # wrong path after MRET
on_misaligned:
    csrr  x31, mtval
    la    x27, misaligned_jal + 6
    sub   x29, x31, x27
    csrr  x31, mepc
    la    x27, misaligned_jal
    sub   x30, x31, x27
    addi  x31, x31, 4
    csrw  mepc, x31
    mret
    jal   x7, fail                  # wrong path after MRET

    # Target of every wrong-path JAL: halts without a register table (the word after the
    # EBREAK is the J), the run fails; a resume of the debugger comes back here.
fail:
    ebreak
    j     fail
