/* Test of sw/riscv: crt0.S, qemu_virt.ld and semihosting.
 *
 * Prints with SEMIHOST_WRITE0 and SEMIHOST_WRITEC, returns 3 from main;
 * crt0.S passes it to semihost_exit, the test expects exit code 3.
 */
#include "semihosting.h"

int main(void)
{
    semihost_write0("semihost_write0 works\n");
    semihost_poll_out('O');
    semihost_poll_out('K');
    semihost_poll_out('\n');
    return 3;
}
