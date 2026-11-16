/* The exit of Mig6's programs: the semihosting exit with the hart's ID in a2.
 *
 * Every hart ends its program with a semihosting exit (crt0.S calls semihost_exit with main's
 * return value). The testbench (test/design/mig6/tb/tb_mig6_debugger.sv) must know which hart
 * exited, and its debug port reads registers, not CSRs, so this exit puts mhartid into a2: a
 * Mig6 convention. It replaces the library's semihost_exit, which is weak
 * (sw/riscv/semihosting/riscv_semihosting.c); csrr is inside the same asm statement as the
 * semihosting sequence, so nothing can use a2 in between.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

#include "semihosting.h"

_Noreturn void semihost_exit(int status)
{
    uint32_t args[2] = {SEMIHOST_STOPPED_APP_EXIT, (uint32_t)status};   // reason, status
    register uint32_t a0 __asm__("a0") = SEMIHOST_EXIT_EXTENDED;
    register uint32_t *a1 __asm__("a1") = args;

    __asm__ volatile(
        ".option push\n"
        ".option norvc\n"
        "csrr a2, mhartid\n"        // the hart's ID, for the testbench
        "slli zero, zero, 0x1f\n"   // semihosting: entry no-op
        "ebreak\n"                  // break to the debugger
        "srai zero, zero, 0x7\n"    // exit no-op
        ".option pop\n"
        : : "r"(a0), "r"(a1) : "a2", "memory");
    __builtin_unreachable();
}
