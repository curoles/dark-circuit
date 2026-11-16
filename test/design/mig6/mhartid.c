/* Prints the hart's ID ("hartid: <n>") and exits with 0, on every PE of TbMig6.
 *
 * The check is the testbench's: every hart must exit once, with its own ID
 * (test/design/mig6/tb/tb_mig6.sv); the line is for people.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

#include "semihosting.h"

int main(void)
{
    uint32_t id;
    char     line[24] = "hartid: ";
    char     digits[11];
    int      n = 0;
    int      i = 8;     // after "hartid: "

    __asm__ volatile("csrr %0, mhartid" : "=r"(id));
    do {
        digits[n++] = (char)('0' + id % 10);
        id /= 10;
    } while (id != 0);
    while (n > 0)
        line[i++] = digits[--n];
    line[i++] = '\n';
    line[i] = '\0';
    semihost_write0(line);
    return 0;
}
