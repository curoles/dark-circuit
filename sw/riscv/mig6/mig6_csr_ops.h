/* THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
 * Generated from rtl/design/mig6/cfg/mig6_csr.yaml and mig6_csr_ops.h.j2 by tools/csr_gen.py
 *
 * Mig6's core CSRs for C programs: a static inline function per access, the only place a
 * program needs a CSR instruction. csr_<name>_read() for every CSR; for a CSR software
 * writes (a field rw, at an address that is not read-only) csr_<name>_write(v), and
 * csr_<name>_set(bits) and csr_<name>_clear(bits) (csrs, csrc: the bits of a mask set or
 * cleared in one instruction, no read-modify-write in the program). The value as fields:
 * the CSR's union of mig6_csr.h,
 *     Mig6CsrMstatus mstatus = {.val = csr_mstatus_read()};
 *     csr_mstatus_set(MIG6_CSR_MSTATUS_MIE_MASK);
 * A write, set or clear clobbers memory, so the compiler keeps memory accesses on their
 * side of it.
 */
#pragma once

#include <stdint.h>

#include "mig6_csr.h"

/* ---- unprivileged_fp ---- */

/* fflags: fcsr's exception flags (a view of fcsr: fflags from bit 0) */
static inline uint32_t csr_fflags_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_FFLAGS));
    return v;
}

static inline void csr_fflags_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_FFLAGS), "r"(v) : "memory");
}

static inline void csr_fflags_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_FFLAGS), "r"(bits) : "memory");
}

static inline void csr_fflags_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_FFLAGS), "r"(bits) : "memory");
}

/* frm: fcsr's rounding mode (a view of fcsr: frm from bit 0) */
static inline uint32_t csr_frm_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_FRM));
    return v;
}

static inline void csr_frm_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_FRM), "r"(v) : "memory");
}

static inline void csr_frm_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_FRM), "r"(bits) : "memory");
}

static inline void csr_frm_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_FRM), "r"(bits) : "memory");
}

/* fcsr: rounding mode and exception flags; an F instruction ORs its flags in */
static inline uint32_t csr_fcsr_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_FCSR));
    return v;
}

static inline void csr_fcsr_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_FCSR), "r"(v) : "memory");
}

static inline void csr_fcsr_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_FCSR), "r"(bits) : "memory");
}

static inline void csr_fcsr_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_FCSR), "r"(bits) : "memory");
}

/* ---- unprivileged_p ---- */

/* vxsat: saturation flag; an instruction that saturated sets it */
static inline uint32_t csr_vxsat_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_VXSAT));
    return v;
}

static inline void csr_vxsat_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_VXSAT), "r"(v) : "memory");
}

static inline void csr_vxsat_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_VXSAT), "r"(bits) : "memory");
}

static inline void csr_vxsat_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_VXSAT), "r"(bits) : "memory");
}

/* ---- unprivileged_counters ---- */

/* cycle: mcycle (a view of mcycle) */
static inline uint32_t csr_cycle_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_CYCLE));
    return v;
}

/* time: mcycle (no real-time clock) (a view of mcycle) */
static inline uint32_t csr_time_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_TIME));
    return v;
}

/* instret: minstret (a view of minstret) */
static inline uint32_t csr_instret_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_INSTRET));
    return v;
}

/* cycleh: mcycleh (a view of mcycleh) */
static inline uint32_t csr_cycleh_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_CYCLEH));
    return v;
}

/* timeh: mcycleh (no real-time clock) (a view of mcycleh) */
static inline uint32_t csr_timeh_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_TIMEH));
    return v;
}

/* instreth: minstreth (a view of minstreth) */
static inline uint32_t csr_instreth_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_INSTRETH));
    return v;
}

/* ---- machine_info ---- */

/* mvendorid: vendor ID, not implemented (0) */
static inline uint32_t csr_mvendorid_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MVENDORID));
    return v;
}

/* marchid: architecture ID, not implemented (0) */
static inline uint32_t csr_marchid_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MARCHID));
    return v;
}

/* mimpid: implementation ID, not implemented (0) */
static inline uint32_t csr_mimpid_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MIMPID));
    return v;
}

/* mhartid: the hart's ID, one per PE */
static inline uint32_t csr_mhartid_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MHARTID));
    return v;
}

/* mnodeid: Mig6's own, the PE's node in the mesh (NocMesh's x, y) */
static inline uint32_t csr_mnodeid_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MNODEID));
    return v;
}

/* ---- machine_trap_setup ---- */

/* mstatus: interrupt enable, before and now; machine mode only */
static inline uint32_t csr_mstatus_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MSTATUS));
    return v;
}

static inline void csr_mstatus_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_MSTATUS), "r"(v) : "memory");
}

static inline void csr_mstatus_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_MSTATUS), "r"(bits) : "memory");
}

static inline void csr_mstatus_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_MSTATUS), "r"(bits) : "memory");
}

/* misa: RV32IMA; writes ignored (Zbb, Zfinx, P have no bit) */
static inline uint32_t csr_misa_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MISA));
    return v;
}

/* mie: interrupt enables; only the machine external interrupt exists */
static inline uint32_t csr_mie_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MIE));
    return v;
}

static inline void csr_mie_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_MIE), "r"(v) : "memory");
}

static inline void csr_mie_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_MIE), "r"(bits) : "memory");
}

static inline void csr_mie_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_MIE), "r"(bits) : "memory");
}

/* mtvec: trap vector, direct mode only (mode bits 1:0 read 0) */
static inline uint32_t csr_mtvec_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MTVEC));
    return v;
}

static inline void csr_mtvec_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_MTVEC), "r"(v) : "memory");
}

static inline void csr_mtvec_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_MTVEC), "r"(bits) : "memory");
}

static inline void csr_mtvec_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_MTVEC), "r"(bits) : "memory");
}

/* mstatush: upper half of mstatus, nothing in it (0) */
static inline uint32_t csr_mstatush_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MSTATUSH));
    return v;
}

/* ---- machine_trap_handling ---- */

/* mscratch: for the trap handler */
static inline uint32_t csr_mscratch_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MSCRATCH));
    return v;
}

static inline void csr_mscratch_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_MSCRATCH), "r"(v) : "memory");
}

static inline void csr_mscratch_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_MSCRATCH), "r"(bits) : "memory");
}

static inline void csr_mscratch_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_MSCRATCH), "r"(bits) : "memory");
}

/* mepc: pc of the trapping instruction (bits 1:0 read 0, no C extension) */
static inline uint32_t csr_mepc_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MEPC));
    return v;
}

static inline void csr_mepc_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_MEPC), "r"(v) : "memory");
}

static inline void csr_mepc_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_MEPC), "r"(bits) : "memory");
}

static inline void csr_mepc_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_MEPC), "r"(bits) : "memory");
}

/* mcause: the trap's cause; bit 31 for an interrupt */
static inline uint32_t csr_mcause_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MCAUSE));
    return v;
}

static inline void csr_mcause_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_MCAUSE), "r"(v) : "memory");
}

static inline void csr_mcause_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_MCAUSE), "r"(bits) : "memory");
}

static inline void csr_mcause_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_MCAUSE), "r"(bits) : "memory");
}

/* mtval: the trap's value (the address, the instruction) */
static inline uint32_t csr_mtval_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MTVAL));
    return v;
}

static inline void csr_mtval_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_MTVAL), "r"(v) : "memory");
}

static inline void csr_mtval_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_MTVAL), "r"(bits) : "memory");
}

static inline void csr_mtval_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_MTVAL), "r"(bits) : "memory");
}

/* mip: pending interrupts; the interrupt controller clears MEIP */
static inline uint32_t csr_mip_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MIP));
    return v;
}

/* ---- machine_counters ---- */

/* mcycle: clocks since reset, low half; a CSR write wins over the count */
static inline uint32_t csr_mcycle_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MCYCLE));
    return v;
}

static inline void csr_mcycle_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_MCYCLE), "r"(v) : "memory");
}

static inline void csr_mcycle_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_MCYCLE), "r"(bits) : "memory");
}

static inline void csr_mcycle_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_MCYCLE), "r"(bits) : "memory");
}

/* minstret: completed instructions (not traps), low half */
static inline uint32_t csr_minstret_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MINSTRET));
    return v;
}

static inline void csr_minstret_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_MINSTRET), "r"(v) : "memory");
}

static inline void csr_minstret_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_MINSTRET), "r"(bits) : "memory");
}

static inline void csr_minstret_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_MINSTRET), "r"(bits) : "memory");
}

/* mcycleh: mcycle, high half */
static inline uint32_t csr_mcycleh_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MCYCLEH));
    return v;
}

static inline void csr_mcycleh_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_MCYCLEH), "r"(v) : "memory");
}

static inline void csr_mcycleh_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_MCYCLEH), "r"(bits) : "memory");
}

static inline void csr_mcycleh_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_MCYCLEH), "r"(bits) : "memory");
}

/* minstreth: minstret, high half */
static inline uint32_t csr_minstreth_read(void)
{
    uint32_t v;
    __asm__ volatile("csrr %0, %1" : "=r"(v) : "i"(MIG6_CSR_MINSTRETH));
    return v;
}

static inline void csr_minstreth_write(uint32_t v)
{
    __asm__ volatile("csrw %0, %1" : : "i"(MIG6_CSR_MINSTRETH), "r"(v) : "memory");
}

static inline void csr_minstreth_set(uint32_t bits)
{
    __asm__ volatile("csrs %0, %1" : : "i"(MIG6_CSR_MINSTRETH), "r"(bits) : "memory");
}

static inline void csr_minstreth_clear(uint32_t bits)
{
    __asm__ volatile("csrc %0, %1" : : "i"(MIG6_CSR_MINSTRETH), "r"(bits) : "memory");
}
