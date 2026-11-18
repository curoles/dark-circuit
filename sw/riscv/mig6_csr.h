/* THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
 * Generated from rtl/design/mig6/cfg/mig6_csr.yaml and mig6_csr.h.j2 by tools/csr_gen.py
 *
 * Mig6's core CSRs for programs and tests, as rtl/design/mig6/cfg/mig6_csr.yaml describes
 * them. First plain numbers, also usable in assembly (.S) and in inline asm. Per CSR:
 * MIG6_CSR_<NAME> its address, _RESET its value after reset, _VALID its bits (the others
 * read 0), _SW_WRITE the bits software writes; per field _<FIELD>_SHIFT its lowest bit,
 * _<FIELD>_MASK its bits in place, _<FIELD>_RESET its value after reset (not for a field
 * that is a hardware signal). A view (another CSR, or some of its fields, at a second
 * address) has its address, _VALID and _SW_WRITE. Then, for C only, a union per CSR,
 * Mig6Csr<Name>: val, the whole value, or its fields by name:
 *     Mig6CsrMstatus mstatus;
 *     mstatus.val = MIG6_CSR_MSTATUS_RESET;
 *     mstatus.mie = 1;
 */
#pragma once

/* ---- unprivileged_fp ---- */

/* fflags: fcsr's exception flags (a view of fcsr: fflags from bit 0) */
#define MIG6_CSR_FFLAGS 0x001
#define MIG6_CSR_FFLAGS_VALID 0x0000001f
#define MIG6_CSR_FFLAGS_SW_WRITE 0x0000001f

/* frm: fcsr's rounding mode (a view of fcsr: frm from bit 0) */
#define MIG6_CSR_FRM 0x002
#define MIG6_CSR_FRM_VALID 0x00000007
#define MIG6_CSR_FRM_SW_WRITE 0x00000007

/* fcsr: rounding mode and exception flags; an F instruction ORs its flags in */
#define MIG6_CSR_FCSR 0x003
#define MIG6_CSR_FCSR_RESET 0x00000000
#define MIG6_CSR_FCSR_VALID 0x000000ff
#define MIG6_CSR_FCSR_SW_WRITE 0x000000ff
#define MIG6_CSR_FCSR_FFLAGS_SHIFT 0
#define MIG6_CSR_FCSR_FFLAGS_MASK 0x0000001f
#define MIG6_CSR_FCSR_FFLAGS_RESET 0
#define MIG6_CSR_FCSR_FRM_SHIFT 5
#define MIG6_CSR_FCSR_FRM_MASK 0x000000e0
#define MIG6_CSR_FCSR_FRM_RESET 0

/* ---- unprivileged_p ---- */

/* vxsat: saturation flag; an instruction that saturated sets it */
#define MIG6_CSR_VXSAT 0x009
#define MIG6_CSR_VXSAT_RESET 0x00000000
#define MIG6_CSR_VXSAT_VALID 0x00000001
#define MIG6_CSR_VXSAT_SW_WRITE 0x00000001
#define MIG6_CSR_VXSAT_SAT_SHIFT 0
#define MIG6_CSR_VXSAT_SAT_MASK 0x00000001
#define MIG6_CSR_VXSAT_SAT_RESET 0

/* ---- unprivileged_counters ---- */

/* cycle: mcycle (a view of mcycle) */
#define MIG6_CSR_CYCLE 0xc00
#define MIG6_CSR_CYCLE_VALID 0xffffffff
#define MIG6_CSR_CYCLE_SW_WRITE 0x00000000

/* time: mcycle (no real-time clock) (a view of mcycle) */
#define MIG6_CSR_TIME 0xc01
#define MIG6_CSR_TIME_VALID 0xffffffff
#define MIG6_CSR_TIME_SW_WRITE 0x00000000

/* instret: minstret (a view of minstret) */
#define MIG6_CSR_INSTRET 0xc02
#define MIG6_CSR_INSTRET_VALID 0xffffffff
#define MIG6_CSR_INSTRET_SW_WRITE 0x00000000

/* cycleh: mcycleh (a view of mcycleh) */
#define MIG6_CSR_CYCLEH 0xc80
#define MIG6_CSR_CYCLEH_VALID 0xffffffff
#define MIG6_CSR_CYCLEH_SW_WRITE 0x00000000

/* timeh: mcycleh (no real-time clock) (a view of mcycleh) */
#define MIG6_CSR_TIMEH 0xc81
#define MIG6_CSR_TIMEH_VALID 0xffffffff
#define MIG6_CSR_TIMEH_SW_WRITE 0x00000000

/* instreth: minstreth (a view of minstreth) */
#define MIG6_CSR_INSTRETH 0xc82
#define MIG6_CSR_INSTRETH_VALID 0xffffffff
#define MIG6_CSR_INSTRETH_SW_WRITE 0x00000000

/* ---- machine_info ---- */

/* mvendorid: vendor ID, not implemented (0) */
#define MIG6_CSR_MVENDORID 0xf11
#define MIG6_CSR_MVENDORID_RESET 0x00000000
#define MIG6_CSR_MVENDORID_VALID 0x00000000
#define MIG6_CSR_MVENDORID_SW_WRITE 0x00000000

/* marchid: architecture ID, not implemented (0) */
#define MIG6_CSR_MARCHID 0xf12
#define MIG6_CSR_MARCHID_RESET 0x00000000
#define MIG6_CSR_MARCHID_VALID 0x00000000
#define MIG6_CSR_MARCHID_SW_WRITE 0x00000000

/* mimpid: implementation ID, not implemented (0) */
#define MIG6_CSR_MIMPID 0xf13
#define MIG6_CSR_MIMPID_RESET 0x00000000
#define MIG6_CSR_MIMPID_VALID 0x00000000
#define MIG6_CSR_MIMPID_SW_WRITE 0x00000000

/* mhartid: the hart's ID, one per PE */
#define MIG6_CSR_MHARTID 0xf14
#define MIG6_CSR_MHARTID_RESET 0x00000000
#define MIG6_CSR_MHARTID_VALID 0xffffffff
#define MIG6_CSR_MHARTID_SW_WRITE 0x00000000
#define MIG6_CSR_MHARTID_ID_SHIFT 0
#define MIG6_CSR_MHARTID_ID_MASK 0xffffffff

/* ---- machine_trap_setup ---- */

/* mstatus: interrupt enable, before and now; machine mode only */
#define MIG6_CSR_MSTATUS 0x300
#define MIG6_CSR_MSTATUS_RESET 0x00001800
#define MIG6_CSR_MSTATUS_VALID 0x00001888
#define MIG6_CSR_MSTATUS_SW_WRITE 0x00000088
#define MIG6_CSR_MSTATUS_MIE_SHIFT 3
#define MIG6_CSR_MSTATUS_MIE_MASK 0x00000008
#define MIG6_CSR_MSTATUS_MIE_RESET 0
#define MIG6_CSR_MSTATUS_MPIE_SHIFT 7
#define MIG6_CSR_MSTATUS_MPIE_MASK 0x00000080
#define MIG6_CSR_MSTATUS_MPIE_RESET 0
#define MIG6_CSR_MSTATUS_MPP_SHIFT 11
#define MIG6_CSR_MSTATUS_MPP_MASK 0x00001800
#define MIG6_CSR_MSTATUS_MPP_RESET 3

/* misa: RV32IMA; writes ignored (Zbb, Zfinx, P have no bit) */
#define MIG6_CSR_MISA 0x301
#define MIG6_CSR_MISA_RESET 0x40001101
#define MIG6_CSR_MISA_VALID 0xc0001101
#define MIG6_CSR_MISA_SW_WRITE 0x00000000
#define MIG6_CSR_MISA_A_SHIFT 0
#define MIG6_CSR_MISA_A_MASK 0x00000001
#define MIG6_CSR_MISA_A_RESET 1
#define MIG6_CSR_MISA_I_SHIFT 8
#define MIG6_CSR_MISA_I_MASK 0x00000100
#define MIG6_CSR_MISA_I_RESET 1
#define MIG6_CSR_MISA_M_SHIFT 12
#define MIG6_CSR_MISA_M_MASK 0x00001000
#define MIG6_CSR_MISA_M_RESET 1
#define MIG6_CSR_MISA_MXL_SHIFT 30
#define MIG6_CSR_MISA_MXL_MASK 0xc0000000
#define MIG6_CSR_MISA_MXL_RESET 1

/* mie: interrupt enables; only the machine external interrupt exists */
#define MIG6_CSR_MIE 0x304
#define MIG6_CSR_MIE_RESET 0x00000000
#define MIG6_CSR_MIE_VALID 0x00000800
#define MIG6_CSR_MIE_SW_WRITE 0x00000800
#define MIG6_CSR_MIE_MEIE_SHIFT 11
#define MIG6_CSR_MIE_MEIE_MASK 0x00000800
#define MIG6_CSR_MIE_MEIE_RESET 0

/* mtvec: trap vector, direct mode only (mode bits 1:0 read 0) */
#define MIG6_CSR_MTVEC 0x305
#define MIG6_CSR_MTVEC_RESET 0x00000000
#define MIG6_CSR_MTVEC_VALID 0xfffffffc
#define MIG6_CSR_MTVEC_SW_WRITE 0xfffffffc
#define MIG6_CSR_MTVEC_BASE_SHIFT 2
#define MIG6_CSR_MTVEC_BASE_MASK 0xfffffffc
#define MIG6_CSR_MTVEC_BASE_RESET 0

/* mstatush: upper half of mstatus, nothing in it (0) */
#define MIG6_CSR_MSTATUSH 0x310
#define MIG6_CSR_MSTATUSH_RESET 0x00000000
#define MIG6_CSR_MSTATUSH_VALID 0x00000000
#define MIG6_CSR_MSTATUSH_SW_WRITE 0x00000000

/* ---- machine_trap_handling ---- */

/* mscratch: for the trap handler */
#define MIG6_CSR_MSCRATCH 0x340
#define MIG6_CSR_MSCRATCH_RESET 0x00000000
#define MIG6_CSR_MSCRATCH_VALID 0xffffffff
#define MIG6_CSR_MSCRATCH_SW_WRITE 0xffffffff
#define MIG6_CSR_MSCRATCH_VALUE_SHIFT 0
#define MIG6_CSR_MSCRATCH_VALUE_MASK 0xffffffff
#define MIG6_CSR_MSCRATCH_VALUE_RESET 0

/* mepc: pc of the trapping instruction (bits 1:0 read 0, no C extension) */
#define MIG6_CSR_MEPC 0x341
#define MIG6_CSR_MEPC_RESET 0x00000000
#define MIG6_CSR_MEPC_VALID 0xfffffffc
#define MIG6_CSR_MEPC_SW_WRITE 0xfffffffc
#define MIG6_CSR_MEPC_PC_SHIFT 2
#define MIG6_CSR_MEPC_PC_MASK 0xfffffffc
#define MIG6_CSR_MEPC_PC_RESET 0

/* mcause: the trap's cause; bit 31 for an interrupt */
#define MIG6_CSR_MCAUSE 0x342
#define MIG6_CSR_MCAUSE_RESET 0x00000000
#define MIG6_CSR_MCAUSE_VALID 0xffffffff
#define MIG6_CSR_MCAUSE_SW_WRITE 0xffffffff
#define MIG6_CSR_MCAUSE_VALUE_SHIFT 0
#define MIG6_CSR_MCAUSE_VALUE_MASK 0xffffffff
#define MIG6_CSR_MCAUSE_VALUE_RESET 0

/* mtval: the trap's value (the address, the instruction) */
#define MIG6_CSR_MTVAL 0x343
#define MIG6_CSR_MTVAL_RESET 0x00000000
#define MIG6_CSR_MTVAL_VALID 0xffffffff
#define MIG6_CSR_MTVAL_SW_WRITE 0xffffffff
#define MIG6_CSR_MTVAL_VALUE_SHIFT 0
#define MIG6_CSR_MTVAL_VALUE_MASK 0xffffffff
#define MIG6_CSR_MTVAL_VALUE_RESET 0

/* mip: pending interrupts; the interrupt controller clears MEIP */
#define MIG6_CSR_MIP 0x344
#define MIG6_CSR_MIP_RESET 0x00000000
#define MIG6_CSR_MIP_VALID 0x00000800
#define MIG6_CSR_MIP_SW_WRITE 0x00000000
#define MIG6_CSR_MIP_MEIP_SHIFT 11
#define MIG6_CSR_MIP_MEIP_MASK 0x00000800

/* ---- machine_counters ---- */

/* mcycle: clocks since reset, low half; a CSR write wins over the count */
#define MIG6_CSR_MCYCLE 0xb00
#define MIG6_CSR_MCYCLE_RESET 0x00000000
#define MIG6_CSR_MCYCLE_VALID 0xffffffff
#define MIG6_CSR_MCYCLE_SW_WRITE 0xffffffff
#define MIG6_CSR_MCYCLE_VALUE_SHIFT 0
#define MIG6_CSR_MCYCLE_VALUE_MASK 0xffffffff
#define MIG6_CSR_MCYCLE_VALUE_RESET 0

/* minstret: completed instructions (not traps), low half */
#define MIG6_CSR_MINSTRET 0xb02
#define MIG6_CSR_MINSTRET_RESET 0x00000000
#define MIG6_CSR_MINSTRET_VALID 0xffffffff
#define MIG6_CSR_MINSTRET_SW_WRITE 0xffffffff
#define MIG6_CSR_MINSTRET_VALUE_SHIFT 0
#define MIG6_CSR_MINSTRET_VALUE_MASK 0xffffffff
#define MIG6_CSR_MINSTRET_VALUE_RESET 0

/* mcycleh: mcycle, high half */
#define MIG6_CSR_MCYCLEH 0xb80
#define MIG6_CSR_MCYCLEH_RESET 0x00000000
#define MIG6_CSR_MCYCLEH_VALID 0xffffffff
#define MIG6_CSR_MCYCLEH_SW_WRITE 0xffffffff
#define MIG6_CSR_MCYCLEH_VALUE_SHIFT 0
#define MIG6_CSR_MCYCLEH_VALUE_MASK 0xffffffff
#define MIG6_CSR_MCYCLEH_VALUE_RESET 0

/* minstreth: minstret, high half */
#define MIG6_CSR_MINSTRETH 0xb82
#define MIG6_CSR_MINSTRETH_RESET 0x00000000
#define MIG6_CSR_MINSTRETH_VALID 0xffffffff
#define MIG6_CSR_MINSTRETH_SW_WRITE 0xffffffff
#define MIG6_CSR_MINSTRETH_VALUE_SHIFT 0
#define MIG6_CSR_MINSTRETH_VALUE_MASK 0xffffffff
#define MIG6_CSR_MINSTRETH_VALUE_RESET 0

#ifndef __ASSEMBLER__
#include <stdint.h>

/* A union per CSR: val, or its fields, bit 0 first (RISC-V's ABI places bit-fields from the
 * lowest bit); zero_<hi>_<lo>: bits that read 0. A view of a whole CSR is its type. */

/* fflags: fcsr's exception flags (a view of fcsr: fflags from bit 0) */
typedef union Mig6CsrFflags {
    uint32_t val;
    struct {
        uint32_t fflags     : 5;
        uint32_t zero_31_5  : 27;
    };
} Mig6CsrFflags;

/* frm: fcsr's rounding mode (a view of fcsr: frm from bit 0) */
typedef union Mig6CsrFrm {
    uint32_t val;
    struct {
        uint32_t frm        : 3;
        uint32_t zero_31_3  : 29;
    };
} Mig6CsrFrm;

/* fcsr: rounding mode and exception flags; an F instruction ORs its flags in */
typedef union Mig6CsrFcsr {
    uint32_t val;
    struct {
        uint32_t fflags     : 5;
        uint32_t frm        : 3;
        uint32_t zero_31_8  : 24;
    };
} Mig6CsrFcsr;

/* vxsat: saturation flag; an instruction that saturated sets it */
typedef union Mig6CsrVxsat {
    uint32_t val;
    struct {
        uint32_t sat        : 1;
        uint32_t zero_31_1  : 31;
    };
} Mig6CsrVxsat;

/* mvendorid: vendor ID, not implemented (0) */
typedef union Mig6CsrMvendorid {
    uint32_t val;
    struct {
        uint32_t zero_31_0  : 32;
    };
} Mig6CsrMvendorid;

/* marchid: architecture ID, not implemented (0) */
typedef union Mig6CsrMarchid {
    uint32_t val;
    struct {
        uint32_t zero_31_0  : 32;
    };
} Mig6CsrMarchid;

/* mimpid: implementation ID, not implemented (0) */
typedef union Mig6CsrMimpid {
    uint32_t val;
    struct {
        uint32_t zero_31_0  : 32;
    };
} Mig6CsrMimpid;

/* mhartid: the hart's ID, one per PE */
typedef union Mig6CsrMhartid {
    uint32_t val;
    struct {
        uint32_t id         : 32;
    };
} Mig6CsrMhartid;

/* mstatus: interrupt enable, before and now; machine mode only */
typedef union Mig6CsrMstatus {
    uint32_t val;
    struct {
        uint32_t zero_2_0   : 3;
        uint32_t mie        : 1;
        uint32_t zero_6_4   : 3;
        uint32_t mpie       : 1;
        uint32_t zero_10_8  : 3;
        uint32_t mpp        : 2;
        uint32_t zero_31_13 : 19;
    };
} Mig6CsrMstatus;

/* misa: RV32IMA; writes ignored (Zbb, Zfinx, P have no bit) */
typedef union Mig6CsrMisa {
    uint32_t val;
    struct {
        uint32_t a          : 1;
        uint32_t zero_7_1   : 7;
        uint32_t i          : 1;
        uint32_t zero_11_9  : 3;
        uint32_t m          : 1;
        uint32_t zero_29_13 : 17;
        uint32_t mxl        : 2;
    };
} Mig6CsrMisa;

/* mie: interrupt enables; only the machine external interrupt exists */
typedef union Mig6CsrMie {
    uint32_t val;
    struct {
        uint32_t zero_10_0  : 11;
        uint32_t meie       : 1;
        uint32_t zero_31_12 : 20;
    };
} Mig6CsrMie;

/* mtvec: trap vector, direct mode only (mode bits 1:0 read 0) */
typedef union Mig6CsrMtvec {
    uint32_t val;
    struct {
        uint32_t zero_1_0   : 2;
        uint32_t base       : 30;
    };
} Mig6CsrMtvec;

/* mstatush: upper half of mstatus, nothing in it (0) */
typedef union Mig6CsrMstatush {
    uint32_t val;
    struct {
        uint32_t zero_31_0  : 32;
    };
} Mig6CsrMstatush;

/* mscratch: for the trap handler */
typedef union Mig6CsrMscratch {
    uint32_t val;
    struct {
        uint32_t value      : 32;
    };
} Mig6CsrMscratch;

/* mepc: pc of the trapping instruction (bits 1:0 read 0, no C extension) */
typedef union Mig6CsrMepc {
    uint32_t val;
    struct {
        uint32_t zero_1_0   : 2;
        uint32_t pc         : 30;
    };
} Mig6CsrMepc;

/* mcause: the trap's cause; bit 31 for an interrupt */
typedef union Mig6CsrMcause {
    uint32_t val;
    struct {
        uint32_t value      : 32;
    };
} Mig6CsrMcause;

/* mtval: the trap's value (the address, the instruction) */
typedef union Mig6CsrMtval {
    uint32_t val;
    struct {
        uint32_t value      : 32;
    };
} Mig6CsrMtval;

/* mip: pending interrupts; the interrupt controller clears MEIP */
typedef union Mig6CsrMip {
    uint32_t val;
    struct {
        uint32_t zero_10_0  : 11;
        uint32_t meip       : 1;
        uint32_t zero_31_12 : 20;
    };
} Mig6CsrMip;

/* mcycle: clocks since reset, low half; a CSR write wins over the count */
typedef union Mig6CsrMcycle {
    uint32_t val;
    struct {
        uint32_t value      : 32;
    };
} Mig6CsrMcycle;

/* minstret: completed instructions (not traps), low half */
typedef union Mig6CsrMinstret {
    uint32_t val;
    struct {
        uint32_t value      : 32;
    };
} Mig6CsrMinstret;

/* mcycleh: mcycle, high half */
typedef union Mig6CsrMcycleh {
    uint32_t val;
    struct {
        uint32_t value      : 32;
    };
} Mig6CsrMcycleh;

/* minstreth: minstret, high half */
typedef union Mig6CsrMinstreth {
    uint32_t val;
    struct {
        uint32_t value      : 32;
    };
} Mig6CsrMinstreth;

/* Views of whole CSRs. */
typedef Mig6CsrMcycle Mig6CsrCycle;
typedef Mig6CsrMcycle Mig6CsrTime;
typedef Mig6CsrMinstret Mig6CsrInstret;
typedef Mig6CsrMcycleh Mig6CsrCycleh;
typedef Mig6CsrMcycleh Mig6CsrTimeh;
typedef Mig6CsrMinstreth Mig6CsrInstreth;

#endif /* __ASSEMBLER__ */
