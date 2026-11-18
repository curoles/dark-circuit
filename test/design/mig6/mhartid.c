/* Prints the hart's ID and its node in the mesh ("hartid: <n> node: <x>,<y>"), on every PE
 * of TbMig6; exits with 1 when the node is not the hart's, else with 0.
 *
 * TbMig6 puts hart p at node (p % MESH_X, p / MESH_X) (Mig6NocPkg); mnodeid, Mig6's own CSR
 * (sw/riscv/mig6_csr_ops.h, from rtl/design/mig6/cfg/mig6_csr.yaml), must read that. The
 * other check is the testbench's: every hart must exit once, with its own ID
 * (test/design/mig6/tb/tb_mig6.sv).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

#include "mig6_csr_ops.h"
#include "tprintf.h"

#define MESH_X 2        /* Mig6NocPkg::MESH_X: PEs in a row */

int main(void)
{
    uint32_t       id   = csr_mhartid_read();
    Mig6CsrMnodeid node = {.val = csr_mnodeid_read()};

    tprintf("hartid: %u node: %u,%u\n", id, node.x, node.y);
    return (node.x == id % MESH_X && node.y == id / MESH_X) ? 0 : 1;
}
