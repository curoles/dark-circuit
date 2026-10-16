/* Startup code of bare-metal RISC-V programs.
 *
 * _start is the first instruction at the reset address, the linker script puts
 * section .text.start first. It sets global pointer and stack pointer, clears .bss,
 * calls main and passes its return value to semihost_exit as exit status.
 * Linker script defines __global_pointer$, __stack_top, __bss_start and __bss_end.
 */
    .section .text.start, "ax"
    .globl _start
_start:
    .option push
    .option norelax          # gp itself must be loaded without gp-relative relaxation
    la      gp, __global_pointer$
    .option pop
    la      sp, __stack_top

    # Clear .bss, the linker script aligns its start and end to 4.
    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b

2:  call    main
    call    semihost_exit    # a0 is the return value of main, does not return
3:  j       3b
