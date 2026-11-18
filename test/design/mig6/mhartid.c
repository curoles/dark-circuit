/* Prints the hart's ID and its node in the mesh ("hartid: <n> node: <x>,<y>"), on every PE
 * of TbMig6; exits with 1 when the node is not the hart's, else with 0.
 *
 * TbMig6 puts hart p at node (p % MESH_X, p / MESH_X) (Mig6NocPkg); mnodeid, Mig6's own CSR
 * (sw/riscv/mig6_csr_ops.h, from rtl/design/mig6/cfg/mig6_csr.yaml), must read that. The other
 * check is the testbench's: every hart must exit once, with its own ID
 * (test/design/mig6/tb/tb_mig6.sv).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

#include "mig6_csr_ops.h"
#include "semihosting.h"

#define MESH_X 2        /* Mig6NocPkg::MESH_X: PEs in a row */

/* Appends the decimal digits of v at line[i]; returns the index after them. */
static int put_dec(char *line, int i, uint32_t v)
{
    char digits[11];
    int  n = 0;

    do {
        digits[n++] = (char)('0' + v % 10);
        v /= 10;
    } while (v != 0);
    while (n > 0)
        line[i++] = digits[--n];
    return i;
}

/* Appends the text s at line[i]; returns the index after it. */
static int put_str(char *line, int i, const char *s)
{
    while (*s != '\0')
        line[i++] = *s++;
    return i;
}

int main(void)
{
    uint32_t       id   = csr_mhartid_read();
    Mig6CsrMnodeid node = {.val = csr_mnodeid_read()};
    char           line[48];
    int            i = 0;

    i = put_str(line, i, "hartid: ");
    i = put_dec(line, i, id);
    i = put_str(line, i, " node: ");
    i = put_dec(line, i, node.x);
    i = put_str(line, i, ",");
    i = put_dec(line, i, node.y);
    i = put_str(line, i, "\n");
    line[i] = '\0';
    semihost_write0(line);
    return (node.x == id % MESH_X && node.y == id / MESH_X) ? 0 : 1;
}
