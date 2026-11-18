/* Reads every standard CSR of Mig6 twice, by the assembler's name and by csr_<name>_read()
 * (sw/riscv/mig6/mig6_csr_ops.h: its address from rtl/design/mig6/cfg/mig6_csr.yaml), on every
 * PE of TbMig6; exits with 1 at the first CSR whose two reads differ, or whose value has a
 * bit outside its MIG6_CSR_<NAME>_VALID, else with 0.
 *
 * First every CSR software writes gets a value of its own (csr_<name>_write()), so that
 * two CSRs swapped in the YAML do not both read 0. The two reads must be equal; a
 * counter's (cycle, time, instret, mcycle, minstret) moves between them, so the second must
 * be above the first by less than 64. So the YAML's addresses are the toolchain's (the
 * spec's), and its bits the hardware's. mnodeid, Mig6's own, has no name: mhartid.c reads
 * it. The name is the reason for the one CSR instruction here (CHECK). Last, a clear and
 * a set of bits of mscratch (csr_mscratch_clear, csr_mscratch_set).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

#include "mig6/mig6_csr_ops.h"
#include "tprintf.h"

static int checked;

/* Prints "csr <name>: <what> <a> <b>" and returns 1, for main to exit with. */
static int fail(const char* name, const char* what, uint32_t a, uint32_t b)
{
    tprintf("csr %s: %s %08x %08x\n", name, what, a, b);
    return 1;
}

/* The CSR by its name and by csr_<name>_read(): equal (counter 0) or a little above
 * (counter 1), and inside its valid bits. */
#define CHECK(name, ADDR, counter)                                                         \
    do {                                                                                   \
        uint32_t a, b;                                                                     \
        __asm__ volatile("csrr %0, " #name : "=r"(a));                                     \
        b = csr_##name##_read();                                                           \
        if ((counter) ? (b - a == 0 || b - a >= 64) : (a != b))                            \
            return fail(#name, "by name, by address", a, b);                               \
        if ((b & ~(uint32_t)ADDR##_VALID) != 0)                                            \
            return fail(#name, "value, valid bits", b, ADDR##_VALID);                      \
        checked++;                                                                         \
    } while (0)

int main(void)
{
    /* A value of its own in every CSR software writes, so that two CSRs swapped in the YAML
     * would not both read 0. None of them makes a trap: no interrupt comes (mie.MEIE
     * without mstatus.MIE, and no source), mtvec is used only by a trap. */
    csr_fcsr_write(0x75u);          /* frm 3, flags NV OF NX */
    csr_vxsat_write(1u);
    csr_mie_write(MIG6_CSR_MIE_MEIE_MASK);
    csr_mtvec_write(0x00000100u);
    csr_mscratch_write(0x13579bdfu);
    csr_mepc_write(0x00001234u);
    csr_mcause_write(0x8000000bu);
    csr_mtval_write(0x2468ace0u);

    CHECK(fflags,    MIG6_CSR_FFLAGS,    0);
    CHECK(frm,       MIG6_CSR_FRM,       0);
    CHECK(fcsr,      MIG6_CSR_FCSR,      0);
    CHECK(vxsat,     MIG6_CSR_VXSAT,     0);
    CHECK(cycle,     MIG6_CSR_CYCLE,     1);
    CHECK(time,      MIG6_CSR_TIME,      1);
    CHECK(instret,   MIG6_CSR_INSTRET,   1);
    CHECK(cycleh,    MIG6_CSR_CYCLEH,    0);
    CHECK(timeh,     MIG6_CSR_TIMEH,     0);
    CHECK(instreth,  MIG6_CSR_INSTRETH,  0);
    CHECK(mvendorid, MIG6_CSR_MVENDORID, 0);
    CHECK(marchid,   MIG6_CSR_MARCHID,   0);
    CHECK(mimpid,    MIG6_CSR_MIMPID,    0);
    CHECK(mhartid,   MIG6_CSR_MHARTID,   0);
    CHECK(mstatus,   MIG6_CSR_MSTATUS,   0);
    CHECK(misa,      MIG6_CSR_MISA,      0);
    CHECK(mie,       MIG6_CSR_MIE,       0);
    CHECK(mtvec,     MIG6_CSR_MTVEC,     0);
    CHECK(mstatush,  MIG6_CSR_MSTATUSH,  0);
    CHECK(mscratch,  MIG6_CSR_MSCRATCH,  0);
    CHECK(mepc,      MIG6_CSR_MEPC,      0);
    CHECK(mcause,    MIG6_CSR_MCAUSE,    0);
    CHECK(mtval,     MIG6_CSR_MTVAL,     0);
    CHECK(mip,       MIG6_CSR_MIP,       0);
    CHECK(mcycle,    MIG6_CSR_MCYCLE,    1);
    CHECK(minstret,  MIG6_CSR_MINSTRET,  1);
    CHECK(mcycleh,   MIG6_CSR_MCYCLEH,   0);
    CHECK(minstreth, MIG6_CSR_MINSTRETH, 0);
    if (checked != 28)
        return fail("count", "checked, expected", checked, 28);

    /* The bit operations of mig6_csr_ops.h, on mscratch (0x13579bdf). */
    csr_mscratch_clear(0x0000ffffu);
    if (csr_mscratch_read() != 0x13570000u)
        return fail("mscratch", "after clear, expected", csr_mscratch_read(), 0x13570000u);
    csr_mscratch_set(0x000000ffu);
    if (csr_mscratch_read() != 0x135700ffu)
        return fail("mscratch", "after set, expected", csr_mscratch_read(), 0x135700ffu);
    return 0;
}
