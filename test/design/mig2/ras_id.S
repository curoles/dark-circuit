/* Program for TbMig2 with +expect_trap +expect_regs: calls and returns in the corners of the
 * pipeline, for a return-address stack in ID (calls push, returns pop; 8 entries).
 *
 * - Recursion 12 deep: the stack of 8 entries wraps; the outer returns find wrong
 *   addresses (the newest entries overwrote them).
 * - A call of an empty function in a loop: the return comes right after the call.
 * - The usual epilogue, lw ra then ret: the return waits in ID for the load data.
 * - A return behind a division: it waits in ID while EX holds the division.
 * - An indirect call (JALR with rd = ra): it pushes like a JAL.
 * - A return to a changed ra (like longjmp): the prediction is wrong; the instruction after
 *   the call must not retire.
 * - A call on the wrong path, right after a branch that goes the other way, in a function:
 *   it must not push (the return of the function must find its caller's address).
 * - Calls that wait in ID, in a function: a JAL behind a division, a JALR waiting for load
 *   data: each must push once (the return of the function must find its caller's address).
 * - A swap, JALR x5, 0(x1) (pop, then push): a coroutine goes back to its caller, is
 *   resumed with JALR x0, 0(x5) and leaves with a plain jump; the return of its caller must
 *   find the caller's own address on top (the swap popped the coroutine's).
 * - Calls in a trap handler (ECALL), with link register x5.
 * Instructions that must not retire set bits in x17 (expect 0); every case counts its runs
 * in a register of its own. Anything unexpected ends at `fail`, an EBREAK without a register
 * table: the run fails. After the halting EBREAK: number of expected registers, then pairs
 * register, value.
 */
    .option norelax

    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    j     start
fail:
    ebreak
    j     fail
start:
    la    x30, handler
    csrw  mtvec, x30
    la    sp, stack_top
    la    x8, save_slot
    li    x24, 100
    li    x25, 7
    addi  x11, x0, 0
    addi  x12, x0, 0
    addi  x13, x0, 0
    addi  x14, x0, 0
    addi  x15, x0, 0
    addi  x17, x0, 0
    addi  x18, x0, 0
    addi  x19, x0, 0
    addi  x23, x0, 0
    addi  x28, x0, 0            # traps

    # Recursion 12 deep.
    li    x10, 12
    jal   ra, rec

    # A call of an empty function in a loop.
    li    x20, 4
1:
    jal   ra, empty
    addi  x12, x12, 1
    addi  x20, x20, -1
    bnez  x20, 1b

    # The epilogue lw ra, ret.
    li    x20, 3
1:
    jal   ra, f_lu
    addi  x20, x20, -1
    bnez  x20, 1b

    # A return behind a division.
    li    x20, 2
1:
    jal   ra, f_div
    addi  x20, x20, -1
    bnez  x20, 1b

    # An indirect call.
    la    x7, f_ind
    li    x20, 2
1:
    jalr  ra, 0(x7)
    addi  x20, x20, -1
    bnez  x20, 1b

    # A return to a changed ra.
    jal   ra, f_jmp
    ori   x17, x17, 0x01
landed:
    addi  x18, x18, 1

    # A call on the wrong path, in a function.
    li    x20, 2
1:
    jal   ra, f_wp
    addi  x19, x19, 1
    addi  x20, x20, -1
    bnez  x20, 1b

    # Calls that wait in ID, in a function.
    jal   ra, f_wait

    # A swap whose popped address must be gone.
    jal   ra, g_swap

    # Calls in a trap handler.
    li    x20, 2
1:
    ecall
    addi  x20, x20, -1
    bnez  x20, 1b

    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 10, 0
    EXPECT_REG 11, 12
    EXPECT_REG 12, 4
    EXPECT_REG 13, 3
    EXPECT_REG 14, 2
    EXPECT_REG 15, 2
    EXPECT_REG 17, 0
    EXPECT_REG 18, 1
    EXPECT_REG 19, 2
    EXPECT_REG 20, 0
    EXPECT_REG 22, 1
    EXPECT_REG 23, 2
    EXPECT_REG 26, 14
    EXPECT_REG 28, 2
expect_end:

    # Traps: only ECALL is expected; the handler calls a function with link register x5 and
    # continues after the ECALL.
handler:
    addi  x28, x28, 1
    csrr  x31, mcause
    addi  x31, x31, -11
    bnez  x31, fail
    jal   x5, h_func
    csrr  x31, mepc
    addi  x31, x31, 4
    csrw  mepc, x31
    mret

h_func:
    addi  x23, x23, 1
    jr    x5                    # a return through x5

rec:
    addi  sp, sp, -16
    sw    ra, 12(sp)
    addi  x11, x11, 1
    addi  x10, x10, -1
    beqz  x10, 1f
    jal   ra, rec
1:
    lw    ra, 12(sp)
    addi  sp, sp, 16
    ret

empty:
    ret

f_lu:
    sw    ra, 0(x8)
    jal   ra, empty
    addi  x13, x13, 1
    lw    ra, 0(x8)
    ret                         # waits in ID for the load

f_div:
    addi  x14, x14, 1
    div   x26, x24, x25
    ret                         # in ID while EX holds the division

f_ind:
    addi  x15, x15, 1
    ret

f_jmp:
    la    ra, landed
    ret                         # predicted: after the call; really: landed

f_never:
    ori   x17, x17, 0x02
    ret

f_wp:
    beq   x0, x0, 2f            # forward taken: the static guess says not taken (first time)
    jal   ra, f_never           # on the wrong path the first time: must not push
2:
    ret                         # pops the address after jal ra, f_wp

f_wait:
    sw    ra, 4(x8)
    div   x26, x24, x25
    jal   ra, empty             # in ID while EX holds the division: pushes once
    la    x7, empty
    sw    x7, 8(x8)
    lw    x7, 8(x8)
    jalr  ra, 0(x7)             # waits in ID for the load data: pushes once
    lw    ra, 4(x8)
    ret                         # pops the address after jal ra, f_wait

g_swap:
    sw    ra, 4(x8)
    jal   ra, co2               # co2 swaps back here
    jalr  x0, 0(x5)             # resume co2 (a return through x5)
g_swap_end:
    lw    ra, 4(x8)
    ret                         # pops the address after jal ra, g_swap: the swap popped co2's

co2:
    jalr  x5, 0(x1)             # swap: back into g_swap
    addi  x22, x22, 1           # resumed
    j     g_swap_end            # a plain jump, not a return

    .data
    .align 4
save_slot:
    .space 12
stack:
    .space 256
stack_top:
