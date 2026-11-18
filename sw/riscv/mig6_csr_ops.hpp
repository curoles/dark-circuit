/* THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
 * Generated from rtl/design/mig6/cfg/mig6_csr.yaml and mig6_csr_ops.hpp.j2 by tools/csr_gen.py
 *
 * Mig6's core CSRs for C++ programs: a namespace per CSR, mig6::csr::<name>, with its
 * address and masks (addr, reset, valid, sw_write; per field <field>_mask, <field>_shift),
 * its union of mig6_csr.h (fields), and read(), and for a CSR software writes write(v),
 * set(bits), clear(bits). They call the C wrappers of mig6_csr_ops.h, the only place with
 * a CSR instruction.
 *     using namespace mig6::csr;
 *     mstatus::set(mstatus::mie_mask);
 *     mstatus::fields s{.val = mstatus::read()};
 */
#pragma once

#include <stdint.h>

extern "C" {
#include "mig6_csr_ops.h"
}

namespace mig6::csr {

// ---- unprivileged_fp ----

// fflags: fcsr's exception flags (a view of fcsr: fflags from bit 0)
namespace fflags {
    constexpr uint32_t addr     = MIG6_CSR_FFLAGS;
    constexpr uint32_t valid    = MIG6_CSR_FFLAGS_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_FFLAGS_SW_WRITE;
    using fields = Mig6CsrFflags;
    inline uint32_t read()               { return csr_fflags_read(); }
    inline void     write(uint32_t v)    { csr_fflags_write(v); }
    inline void     set(uint32_t bits)   { csr_fflags_set(bits); }
    inline void     clear(uint32_t bits) { csr_fflags_clear(bits); }
}   // namespace fflags

// frm: fcsr's rounding mode (a view of fcsr: frm from bit 0)
namespace frm {
    constexpr uint32_t addr     = MIG6_CSR_FRM;
    constexpr uint32_t valid    = MIG6_CSR_FRM_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_FRM_SW_WRITE;
    using fields = Mig6CsrFrm;
    inline uint32_t read()               { return csr_frm_read(); }
    inline void     write(uint32_t v)    { csr_frm_write(v); }
    inline void     set(uint32_t bits)   { csr_frm_set(bits); }
    inline void     clear(uint32_t bits) { csr_frm_clear(bits); }
}   // namespace frm

// fcsr: rounding mode and exception flags; an F instruction ORs its flags in
namespace fcsr {
    constexpr uint32_t addr         = MIG6_CSR_FCSR;
    constexpr uint32_t reset        = MIG6_CSR_FCSR_RESET;
    constexpr uint32_t valid        = MIG6_CSR_FCSR_VALID;
    constexpr uint32_t sw_write     = MIG6_CSR_FCSR_SW_WRITE;
    constexpr uint32_t fflags_mask  = MIG6_CSR_FCSR_FFLAGS_MASK;
    constexpr uint32_t fflags_shift = MIG6_CSR_FCSR_FFLAGS_SHIFT;
    constexpr uint32_t frm_mask     = MIG6_CSR_FCSR_FRM_MASK;
    constexpr uint32_t frm_shift    = MIG6_CSR_FCSR_FRM_SHIFT;
    using fields = Mig6CsrFcsr;
    inline uint32_t read()               { return csr_fcsr_read(); }
    inline void     write(uint32_t v)    { csr_fcsr_write(v); }
    inline void     set(uint32_t bits)   { csr_fcsr_set(bits); }
    inline void     clear(uint32_t bits) { csr_fcsr_clear(bits); }
}   // namespace fcsr

// ---- unprivileged_p ----

// vxsat: saturation flag; an instruction that saturated sets it
namespace vxsat {
    constexpr uint32_t addr      = MIG6_CSR_VXSAT;
    constexpr uint32_t reset     = MIG6_CSR_VXSAT_RESET;
    constexpr uint32_t valid     = MIG6_CSR_VXSAT_VALID;
    constexpr uint32_t sw_write  = MIG6_CSR_VXSAT_SW_WRITE;
    constexpr uint32_t sat_mask  = MIG6_CSR_VXSAT_SAT_MASK;
    constexpr uint32_t sat_shift = MIG6_CSR_VXSAT_SAT_SHIFT;
    using fields = Mig6CsrVxsat;
    inline uint32_t read()               { return csr_vxsat_read(); }
    inline void     write(uint32_t v)    { csr_vxsat_write(v); }
    inline void     set(uint32_t bits)   { csr_vxsat_set(bits); }
    inline void     clear(uint32_t bits) { csr_vxsat_clear(bits); }
}   // namespace vxsat

// ---- unprivileged_counters ----

// cycle: mcycle (a view of mcycle)
namespace cycle {
    constexpr uint32_t addr     = MIG6_CSR_CYCLE;
    constexpr uint32_t valid    = MIG6_CSR_CYCLE_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_CYCLE_SW_WRITE;
    using fields = Mig6CsrCycle;
    inline uint32_t read()               { return csr_cycle_read(); }
}   // namespace cycle

// time: mcycle (no real-time clock) (a view of mcycle)
namespace time {
    constexpr uint32_t addr     = MIG6_CSR_TIME;
    constexpr uint32_t valid    = MIG6_CSR_TIME_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_TIME_SW_WRITE;
    using fields = Mig6CsrTime;
    inline uint32_t read()               { return csr_time_read(); }
}   // namespace time

// instret: minstret (a view of minstret)
namespace instret {
    constexpr uint32_t addr     = MIG6_CSR_INSTRET;
    constexpr uint32_t valid    = MIG6_CSR_INSTRET_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_INSTRET_SW_WRITE;
    using fields = Mig6CsrInstret;
    inline uint32_t read()               { return csr_instret_read(); }
}   // namespace instret

// cycleh: mcycleh (a view of mcycleh)
namespace cycleh {
    constexpr uint32_t addr     = MIG6_CSR_CYCLEH;
    constexpr uint32_t valid    = MIG6_CSR_CYCLEH_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_CYCLEH_SW_WRITE;
    using fields = Mig6CsrCycleh;
    inline uint32_t read()               { return csr_cycleh_read(); }
}   // namespace cycleh

// timeh: mcycleh (no real-time clock) (a view of mcycleh)
namespace timeh {
    constexpr uint32_t addr     = MIG6_CSR_TIMEH;
    constexpr uint32_t valid    = MIG6_CSR_TIMEH_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_TIMEH_SW_WRITE;
    using fields = Mig6CsrTimeh;
    inline uint32_t read()               { return csr_timeh_read(); }
}   // namespace timeh

// instreth: minstreth (a view of minstreth)
namespace instreth {
    constexpr uint32_t addr     = MIG6_CSR_INSTRETH;
    constexpr uint32_t valid    = MIG6_CSR_INSTRETH_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_INSTRETH_SW_WRITE;
    using fields = Mig6CsrInstreth;
    inline uint32_t read()               { return csr_instreth_read(); }
}   // namespace instreth

// ---- machine_info ----

// mvendorid: vendor ID, not implemented (0)
namespace mvendorid {
    constexpr uint32_t addr     = MIG6_CSR_MVENDORID;
    constexpr uint32_t reset    = MIG6_CSR_MVENDORID_RESET;
    constexpr uint32_t valid    = MIG6_CSR_MVENDORID_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_MVENDORID_SW_WRITE;
    using fields = Mig6CsrMvendorid;
    inline uint32_t read()               { return csr_mvendorid_read(); }
}   // namespace mvendorid

// marchid: architecture ID, not implemented (0)
namespace marchid {
    constexpr uint32_t addr     = MIG6_CSR_MARCHID;
    constexpr uint32_t reset    = MIG6_CSR_MARCHID_RESET;
    constexpr uint32_t valid    = MIG6_CSR_MARCHID_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_MARCHID_SW_WRITE;
    using fields = Mig6CsrMarchid;
    inline uint32_t read()               { return csr_marchid_read(); }
}   // namespace marchid

// mimpid: implementation ID, not implemented (0)
namespace mimpid {
    constexpr uint32_t addr     = MIG6_CSR_MIMPID;
    constexpr uint32_t reset    = MIG6_CSR_MIMPID_RESET;
    constexpr uint32_t valid    = MIG6_CSR_MIMPID_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_MIMPID_SW_WRITE;
    using fields = Mig6CsrMimpid;
    inline uint32_t read()               { return csr_mimpid_read(); }
}   // namespace mimpid

// mhartid: the hart's ID, one per PE
namespace mhartid {
    constexpr uint32_t addr     = MIG6_CSR_MHARTID;
    constexpr uint32_t reset    = MIG6_CSR_MHARTID_RESET;
    constexpr uint32_t valid    = MIG6_CSR_MHARTID_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_MHARTID_SW_WRITE;
    constexpr uint32_t id_mask  = MIG6_CSR_MHARTID_ID_MASK;
    constexpr uint32_t id_shift = MIG6_CSR_MHARTID_ID_SHIFT;
    using fields = Mig6CsrMhartid;
    inline uint32_t read()               { return csr_mhartid_read(); }
}   // namespace mhartid

// mnodeid: Mig6's own, the PE's node in the mesh (NocMesh's x, y)
namespace mnodeid {
    constexpr uint32_t addr     = MIG6_CSR_MNODEID;
    constexpr uint32_t reset    = MIG6_CSR_MNODEID_RESET;
    constexpr uint32_t valid    = MIG6_CSR_MNODEID_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_MNODEID_SW_WRITE;
    constexpr uint32_t x_mask   = MIG6_CSR_MNODEID_X_MASK;
    constexpr uint32_t x_shift  = MIG6_CSR_MNODEID_X_SHIFT;
    constexpr uint32_t y_mask   = MIG6_CSR_MNODEID_Y_MASK;
    constexpr uint32_t y_shift  = MIG6_CSR_MNODEID_Y_SHIFT;
    using fields = Mig6CsrMnodeid;
    inline uint32_t read()               { return csr_mnodeid_read(); }
}   // namespace mnodeid

// ---- machine_trap_setup ----

// mstatus: interrupt enable, before and now; machine mode only
namespace mstatus {
    constexpr uint32_t addr       = MIG6_CSR_MSTATUS;
    constexpr uint32_t reset      = MIG6_CSR_MSTATUS_RESET;
    constexpr uint32_t valid      = MIG6_CSR_MSTATUS_VALID;
    constexpr uint32_t sw_write   = MIG6_CSR_MSTATUS_SW_WRITE;
    constexpr uint32_t mie_mask   = MIG6_CSR_MSTATUS_MIE_MASK;
    constexpr uint32_t mie_shift  = MIG6_CSR_MSTATUS_MIE_SHIFT;
    constexpr uint32_t mpie_mask  = MIG6_CSR_MSTATUS_MPIE_MASK;
    constexpr uint32_t mpie_shift = MIG6_CSR_MSTATUS_MPIE_SHIFT;
    constexpr uint32_t mpp_mask   = MIG6_CSR_MSTATUS_MPP_MASK;
    constexpr uint32_t mpp_shift  = MIG6_CSR_MSTATUS_MPP_SHIFT;
    using fields = Mig6CsrMstatus;
    inline uint32_t read()               { return csr_mstatus_read(); }
    inline void     write(uint32_t v)    { csr_mstatus_write(v); }
    inline void     set(uint32_t bits)   { csr_mstatus_set(bits); }
    inline void     clear(uint32_t bits) { csr_mstatus_clear(bits); }
}   // namespace mstatus

// misa: RV32IMA; writes ignored (Zbb, Zfinx, P have no bit)
namespace misa {
    constexpr uint32_t addr      = MIG6_CSR_MISA;
    constexpr uint32_t reset     = MIG6_CSR_MISA_RESET;
    constexpr uint32_t valid     = MIG6_CSR_MISA_VALID;
    constexpr uint32_t sw_write  = MIG6_CSR_MISA_SW_WRITE;
    constexpr uint32_t a_mask    = MIG6_CSR_MISA_A_MASK;
    constexpr uint32_t a_shift   = MIG6_CSR_MISA_A_SHIFT;
    constexpr uint32_t i_mask    = MIG6_CSR_MISA_I_MASK;
    constexpr uint32_t i_shift   = MIG6_CSR_MISA_I_SHIFT;
    constexpr uint32_t m_mask    = MIG6_CSR_MISA_M_MASK;
    constexpr uint32_t m_shift   = MIG6_CSR_MISA_M_SHIFT;
    constexpr uint32_t mxl_mask  = MIG6_CSR_MISA_MXL_MASK;
    constexpr uint32_t mxl_shift = MIG6_CSR_MISA_MXL_SHIFT;
    using fields = Mig6CsrMisa;
    inline uint32_t read()               { return csr_misa_read(); }
}   // namespace misa

// mie: interrupt enables; only the machine external interrupt exists
namespace mie {
    constexpr uint32_t addr       = MIG6_CSR_MIE;
    constexpr uint32_t reset      = MIG6_CSR_MIE_RESET;
    constexpr uint32_t valid      = MIG6_CSR_MIE_VALID;
    constexpr uint32_t sw_write   = MIG6_CSR_MIE_SW_WRITE;
    constexpr uint32_t meie_mask  = MIG6_CSR_MIE_MEIE_MASK;
    constexpr uint32_t meie_shift = MIG6_CSR_MIE_MEIE_SHIFT;
    using fields = Mig6CsrMie;
    inline uint32_t read()               { return csr_mie_read(); }
    inline void     write(uint32_t v)    { csr_mie_write(v); }
    inline void     set(uint32_t bits)   { csr_mie_set(bits); }
    inline void     clear(uint32_t bits) { csr_mie_clear(bits); }
}   // namespace mie

// mtvec: trap vector, direct mode only (mode bits 1:0 read 0)
namespace mtvec {
    constexpr uint32_t addr       = MIG6_CSR_MTVEC;
    constexpr uint32_t reset      = MIG6_CSR_MTVEC_RESET;
    constexpr uint32_t valid      = MIG6_CSR_MTVEC_VALID;
    constexpr uint32_t sw_write   = MIG6_CSR_MTVEC_SW_WRITE;
    constexpr uint32_t base_mask  = MIG6_CSR_MTVEC_BASE_MASK;
    constexpr uint32_t base_shift = MIG6_CSR_MTVEC_BASE_SHIFT;
    using fields = Mig6CsrMtvec;
    inline uint32_t read()               { return csr_mtvec_read(); }
    inline void     write(uint32_t v)    { csr_mtvec_write(v); }
    inline void     set(uint32_t bits)   { csr_mtvec_set(bits); }
    inline void     clear(uint32_t bits) { csr_mtvec_clear(bits); }
}   // namespace mtvec

// mstatush: upper half of mstatus, nothing in it (0)
namespace mstatush {
    constexpr uint32_t addr     = MIG6_CSR_MSTATUSH;
    constexpr uint32_t reset    = MIG6_CSR_MSTATUSH_RESET;
    constexpr uint32_t valid    = MIG6_CSR_MSTATUSH_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_MSTATUSH_SW_WRITE;
    using fields = Mig6CsrMstatush;
    inline uint32_t read()               { return csr_mstatush_read(); }
}   // namespace mstatush

// ---- machine_trap_handling ----

// mscratch: for the trap handler
namespace mscratch {
    constexpr uint32_t addr        = MIG6_CSR_MSCRATCH;
    constexpr uint32_t reset       = MIG6_CSR_MSCRATCH_RESET;
    constexpr uint32_t valid       = MIG6_CSR_MSCRATCH_VALID;
    constexpr uint32_t sw_write    = MIG6_CSR_MSCRATCH_SW_WRITE;
    constexpr uint32_t value_mask  = MIG6_CSR_MSCRATCH_VALUE_MASK;
    constexpr uint32_t value_shift = MIG6_CSR_MSCRATCH_VALUE_SHIFT;
    using fields = Mig6CsrMscratch;
    inline uint32_t read()               { return csr_mscratch_read(); }
    inline void     write(uint32_t v)    { csr_mscratch_write(v); }
    inline void     set(uint32_t bits)   { csr_mscratch_set(bits); }
    inline void     clear(uint32_t bits) { csr_mscratch_clear(bits); }
}   // namespace mscratch

// mepc: pc of the trapping instruction (bits 1:0 read 0, no C extension)
namespace mepc {
    constexpr uint32_t addr     = MIG6_CSR_MEPC;
    constexpr uint32_t reset    = MIG6_CSR_MEPC_RESET;
    constexpr uint32_t valid    = MIG6_CSR_MEPC_VALID;
    constexpr uint32_t sw_write = MIG6_CSR_MEPC_SW_WRITE;
    constexpr uint32_t pc_mask  = MIG6_CSR_MEPC_PC_MASK;
    constexpr uint32_t pc_shift = MIG6_CSR_MEPC_PC_SHIFT;
    using fields = Mig6CsrMepc;
    inline uint32_t read()               { return csr_mepc_read(); }
    inline void     write(uint32_t v)    { csr_mepc_write(v); }
    inline void     set(uint32_t bits)   { csr_mepc_set(bits); }
    inline void     clear(uint32_t bits) { csr_mepc_clear(bits); }
}   // namespace mepc

// mcause: the trap's cause; bit 31 for an interrupt
namespace mcause {
    constexpr uint32_t addr        = MIG6_CSR_MCAUSE;
    constexpr uint32_t reset       = MIG6_CSR_MCAUSE_RESET;
    constexpr uint32_t valid       = MIG6_CSR_MCAUSE_VALID;
    constexpr uint32_t sw_write    = MIG6_CSR_MCAUSE_SW_WRITE;
    constexpr uint32_t value_mask  = MIG6_CSR_MCAUSE_VALUE_MASK;
    constexpr uint32_t value_shift = MIG6_CSR_MCAUSE_VALUE_SHIFT;
    using fields = Mig6CsrMcause;
    inline uint32_t read()               { return csr_mcause_read(); }
    inline void     write(uint32_t v)    { csr_mcause_write(v); }
    inline void     set(uint32_t bits)   { csr_mcause_set(bits); }
    inline void     clear(uint32_t bits) { csr_mcause_clear(bits); }
}   // namespace mcause

// mtval: the trap's value (the address, the instruction)
namespace mtval {
    constexpr uint32_t addr        = MIG6_CSR_MTVAL;
    constexpr uint32_t reset       = MIG6_CSR_MTVAL_RESET;
    constexpr uint32_t valid       = MIG6_CSR_MTVAL_VALID;
    constexpr uint32_t sw_write    = MIG6_CSR_MTVAL_SW_WRITE;
    constexpr uint32_t value_mask  = MIG6_CSR_MTVAL_VALUE_MASK;
    constexpr uint32_t value_shift = MIG6_CSR_MTVAL_VALUE_SHIFT;
    using fields = Mig6CsrMtval;
    inline uint32_t read()               { return csr_mtval_read(); }
    inline void     write(uint32_t v)    { csr_mtval_write(v); }
    inline void     set(uint32_t bits)   { csr_mtval_set(bits); }
    inline void     clear(uint32_t bits) { csr_mtval_clear(bits); }
}   // namespace mtval

// mip: pending interrupts; the interrupt controller clears MEIP
namespace mip {
    constexpr uint32_t addr       = MIG6_CSR_MIP;
    constexpr uint32_t reset      = MIG6_CSR_MIP_RESET;
    constexpr uint32_t valid      = MIG6_CSR_MIP_VALID;
    constexpr uint32_t sw_write   = MIG6_CSR_MIP_SW_WRITE;
    constexpr uint32_t meip_mask  = MIG6_CSR_MIP_MEIP_MASK;
    constexpr uint32_t meip_shift = MIG6_CSR_MIP_MEIP_SHIFT;
    using fields = Mig6CsrMip;
    inline uint32_t read()               { return csr_mip_read(); }
}   // namespace mip

// ---- machine_counters ----

// mcycle: clocks since reset, low half; a CSR write wins over the count
namespace mcycle {
    constexpr uint32_t addr        = MIG6_CSR_MCYCLE;
    constexpr uint32_t reset       = MIG6_CSR_MCYCLE_RESET;
    constexpr uint32_t valid       = MIG6_CSR_MCYCLE_VALID;
    constexpr uint32_t sw_write    = MIG6_CSR_MCYCLE_SW_WRITE;
    constexpr uint32_t value_mask  = MIG6_CSR_MCYCLE_VALUE_MASK;
    constexpr uint32_t value_shift = MIG6_CSR_MCYCLE_VALUE_SHIFT;
    using fields = Mig6CsrMcycle;
    inline uint32_t read()               { return csr_mcycle_read(); }
    inline void     write(uint32_t v)    { csr_mcycle_write(v); }
    inline void     set(uint32_t bits)   { csr_mcycle_set(bits); }
    inline void     clear(uint32_t bits) { csr_mcycle_clear(bits); }
}   // namespace mcycle

// minstret: completed instructions (not traps), low half
namespace minstret {
    constexpr uint32_t addr        = MIG6_CSR_MINSTRET;
    constexpr uint32_t reset       = MIG6_CSR_MINSTRET_RESET;
    constexpr uint32_t valid       = MIG6_CSR_MINSTRET_VALID;
    constexpr uint32_t sw_write    = MIG6_CSR_MINSTRET_SW_WRITE;
    constexpr uint32_t value_mask  = MIG6_CSR_MINSTRET_VALUE_MASK;
    constexpr uint32_t value_shift = MIG6_CSR_MINSTRET_VALUE_SHIFT;
    using fields = Mig6CsrMinstret;
    inline uint32_t read()               { return csr_minstret_read(); }
    inline void     write(uint32_t v)    { csr_minstret_write(v); }
    inline void     set(uint32_t bits)   { csr_minstret_set(bits); }
    inline void     clear(uint32_t bits) { csr_minstret_clear(bits); }
}   // namespace minstret

// mcycleh: mcycle, high half
namespace mcycleh {
    constexpr uint32_t addr        = MIG6_CSR_MCYCLEH;
    constexpr uint32_t reset       = MIG6_CSR_MCYCLEH_RESET;
    constexpr uint32_t valid       = MIG6_CSR_MCYCLEH_VALID;
    constexpr uint32_t sw_write    = MIG6_CSR_MCYCLEH_SW_WRITE;
    constexpr uint32_t value_mask  = MIG6_CSR_MCYCLEH_VALUE_MASK;
    constexpr uint32_t value_shift = MIG6_CSR_MCYCLEH_VALUE_SHIFT;
    using fields = Mig6CsrMcycleh;
    inline uint32_t read()               { return csr_mcycleh_read(); }
    inline void     write(uint32_t v)    { csr_mcycleh_write(v); }
    inline void     set(uint32_t bits)   { csr_mcycleh_set(bits); }
    inline void     clear(uint32_t bits) { csr_mcycleh_clear(bits); }
}   // namespace mcycleh

// minstreth: minstret, high half
namespace minstreth {
    constexpr uint32_t addr        = MIG6_CSR_MINSTRETH;
    constexpr uint32_t reset       = MIG6_CSR_MINSTRETH_RESET;
    constexpr uint32_t valid       = MIG6_CSR_MINSTRETH_VALID;
    constexpr uint32_t sw_write    = MIG6_CSR_MINSTRETH_SW_WRITE;
    constexpr uint32_t value_mask  = MIG6_CSR_MINSTRETH_VALUE_MASK;
    constexpr uint32_t value_shift = MIG6_CSR_MINSTRETH_VALUE_SHIFT;
    using fields = Mig6CsrMinstreth;
    inline uint32_t read()               { return csr_minstreth_read(); }
    inline void     write(uint32_t v)    { csr_minstreth_write(v); }
    inline void     set(uint32_t bits)   { csr_minstreth_set(bits); }
    inline void     clear(uint32_t bits) { csr_minstreth_clear(bits); }
}   // namespace minstreth

}   // namespace mig6::csr
