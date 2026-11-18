// THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
// Generated from rtl/design/mig6/cfg/mig6_csr.yaml and mig6_csr_pkg.sv.j2 by tools/csr_gen.py
//
// Mig6's core CSRs (AGENTS.md, Terminology), as cfg/mig6_csr.yaml describes them. Per CSR:
// <NAME>_ADDR its address, <NAME>_RESET its value after reset, <NAME>_VALID its bits (the
// others read 0), <NAME>_SW_WRITE the bits software writes, <NAME>_CONST the bits that are
// always their reset value, and <name>_t, a packed struct of its fields (zero_<hi>_<lo>:
// bits that read 0). A view (another CSR, or some of its fields, at a second address) has
// its address, valid and SW_WRITE bits. csr_state_t holds every CSR a design keeps or wires
// (not all constant); csr_read gives the value of the CSR at an address from it, and
// whether one is there; csr_write_merge gives a CSR's value after software writes wdata.
package Mig6CsrPkg;

    // Every CSR's constants; a design uses some.
    /* verilator lint_off UNUSEDPARAM */

    // ---- unprivileged_fp ----

    // fflags: fcsr's exception flags (a view of fcsr: fflags from bit 0)
    localparam logic [11:0] FFLAGS_ADDR     = 12'h001;
    localparam logic [31:0] FFLAGS_VALID    = 32'h0000_001f;
    localparam logic [31:0] FFLAGS_SW_WRITE = 32'h0000_001f;

    // frm: fcsr's rounding mode (a view of fcsr: frm from bit 0)
    localparam logic [11:0] FRM_ADDR     = 12'h002;
    localparam logic [31:0] FRM_VALID    = 32'h0000_0007;
    localparam logic [31:0] FRM_SW_WRITE = 32'h0000_0007;

    // fcsr: rounding mode and exception flags; an F instruction ORs its flags in
    localparam logic [11:0] FCSR_ADDR     = 12'h003;
    localparam logic [31:0] FCSR_RESET    = 32'h0000_0000;
    localparam logic [31:0] FCSR_VALID    = 32'h0000_00ff;
    localparam logic [31:0] FCSR_SW_WRITE = 32'h0000_00ff;
    localparam logic [31:0] FCSR_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [23:0] zero_31_8;
        logic [2:0]  frm;       // 7:5, sw rw, hw none, reset 0
        logic [4:0]  fflags;    // 4:0, sw rw, hw write, reset 0
    } fcsr_t;

    // ---- unprivileged_p ----

    // vxsat: saturation flag; an instruction that saturated sets it
    localparam logic [11:0] VXSAT_ADDR     = 12'h009;
    localparam logic [31:0] VXSAT_RESET    = 32'h0000_0000;
    localparam logic [31:0] VXSAT_VALID    = 32'h0000_0001;
    localparam logic [31:0] VXSAT_SW_WRITE = 32'h0000_0001;
    localparam logic [31:0] VXSAT_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [30:0] zero_31_1;
        logic        sat;       // 0, sw rw, hw write, reset 0
    } vxsat_t;

    // ---- unprivileged_counters ----

    // cycle: mcycle (a view of mcycle)
    localparam logic [11:0] CYCLE_ADDR     = 12'hc00;
    localparam logic [31:0] CYCLE_VALID    = 32'hffff_ffff;
    localparam logic [31:0] CYCLE_SW_WRITE = 32'h0000_0000;

    // time: mcycle (no real-time clock) (a view of mcycle)
    localparam logic [11:0] TIME_ADDR     = 12'hc01;
    localparam logic [31:0] TIME_VALID    = 32'hffff_ffff;
    localparam logic [31:0] TIME_SW_WRITE = 32'h0000_0000;

    // instret: minstret (a view of minstret)
    localparam logic [11:0] INSTRET_ADDR     = 12'hc02;
    localparam logic [31:0] INSTRET_VALID    = 32'hffff_ffff;
    localparam logic [31:0] INSTRET_SW_WRITE = 32'h0000_0000;

    // cycleh: mcycleh (a view of mcycleh)
    localparam logic [11:0] CYCLEH_ADDR     = 12'hc80;
    localparam logic [31:0] CYCLEH_VALID    = 32'hffff_ffff;
    localparam logic [31:0] CYCLEH_SW_WRITE = 32'h0000_0000;

    // timeh: mcycleh (no real-time clock) (a view of mcycleh)
    localparam logic [11:0] TIMEH_ADDR     = 12'hc81;
    localparam logic [31:0] TIMEH_VALID    = 32'hffff_ffff;
    localparam logic [31:0] TIMEH_SW_WRITE = 32'h0000_0000;

    // instreth: minstreth (a view of minstreth)
    localparam logic [11:0] INSTRETH_ADDR     = 12'hc82;
    localparam logic [31:0] INSTRETH_VALID    = 32'hffff_ffff;
    localparam logic [31:0] INSTRETH_SW_WRITE = 32'h0000_0000;

    // ---- machine_info ----

    // mvendorid: vendor ID, not implemented (0)
    localparam logic [11:0] MVENDORID_ADDR     = 12'hf11;
    localparam logic [31:0] MVENDORID_RESET    = 32'h0000_0000;
    localparam logic [31:0] MVENDORID_VALID    = 32'h0000_0000;
    localparam logic [31:0] MVENDORID_SW_WRITE = 32'h0000_0000;
    localparam logic [31:0] MVENDORID_CONST    = 32'h0000_0000;

    // marchid: architecture ID, not implemented (0)
    localparam logic [11:0] MARCHID_ADDR     = 12'hf12;
    localparam logic [31:0] MARCHID_RESET    = 32'h0000_0000;
    localparam logic [31:0] MARCHID_VALID    = 32'h0000_0000;
    localparam logic [31:0] MARCHID_SW_WRITE = 32'h0000_0000;
    localparam logic [31:0] MARCHID_CONST    = 32'h0000_0000;

    // mimpid: implementation ID, not implemented (0)
    localparam logic [11:0] MIMPID_ADDR     = 12'hf13;
    localparam logic [31:0] MIMPID_RESET    = 32'h0000_0000;
    localparam logic [31:0] MIMPID_VALID    = 32'h0000_0000;
    localparam logic [31:0] MIMPID_SW_WRITE = 32'h0000_0000;
    localparam logic [31:0] MIMPID_CONST    = 32'h0000_0000;

    // mhartid: the hart's ID, one per PE
    localparam logic [11:0] MHARTID_ADDR     = 12'hf14;
    localparam logic [31:0] MHARTID_RESET    = 32'h0000_0000;
    localparam logic [31:0] MHARTID_VALID    = 32'hffff_ffff;
    localparam logic [31:0] MHARTID_SW_WRITE = 32'h0000_0000;
    localparam logic [31:0] MHARTID_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [31:0] id;        // 31:0, sw ro, hw live, from HART_ID
    } mhartid_t;

    // ---- machine_trap_setup ----

    // mstatus: interrupt enable, before and now; machine mode only
    localparam logic [11:0] MSTATUS_ADDR     = 12'h300;
    localparam logic [31:0] MSTATUS_RESET    = 32'h0000_1800;
    localparam logic [31:0] MSTATUS_VALID    = 32'h0000_1888;
    localparam logic [31:0] MSTATUS_SW_WRITE = 32'h0000_0088;
    localparam logic [31:0] MSTATUS_CONST    = 32'h0000_1800;
    typedef struct packed {
        logic [18:0] zero_31_13;
        logic [1:0]  mpp;       // 12:11, sw ro, hw none, reset 3
        logic [2:0]  zero_10_8;
        logic        mpie;      // 7, sw rw, hw write, reset 0
        logic [2:0]  zero_6_4;
        logic        mie;       // 3, sw rw, hw write, reset 0
        logic [2:0]  zero_2_0;
    } mstatus_t;

    // misa: RV32IMA; writes ignored (Zbb, Zfinx, P have no bit)
    localparam logic [11:0] MISA_ADDR     = 12'h301;
    localparam logic [31:0] MISA_RESET    = 32'h4000_1101;
    localparam logic [31:0] MISA_VALID    = 32'hc000_1101;
    localparam logic [31:0] MISA_SW_WRITE = 32'h0000_0000;
    localparam logic [31:0] MISA_CONST    = 32'hc000_1101;
    typedef struct packed {
        logic [1:0]  mxl;       // 31:30, sw ro, hw none, reset 1
        logic [16:0] zero_29_13;
        logic        m;         // 12, sw ro, hw none, reset 1
        logic [2:0]  zero_11_9;
        logic        i;         // 8, sw ro, hw none, reset 1
        logic [6:0]  zero_7_1;
        logic        a;         // 0, sw ro, hw none, reset 1
    } misa_t;

    // mie: interrupt enables; only the machine external interrupt exists
    localparam logic [11:0] MIE_ADDR     = 12'h304;
    localparam logic [31:0] MIE_RESET    = 32'h0000_0000;
    localparam logic [31:0] MIE_VALID    = 32'h0000_0800;
    localparam logic [31:0] MIE_SW_WRITE = 32'h0000_0800;
    localparam logic [31:0] MIE_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [19:0] zero_31_12;
        logic        meie;      // 11, sw rw, hw none, reset 0
        logic [10:0] zero_10_0;
    } mie_t;

    // mtvec: trap vector, direct mode only (mode bits 1:0 read 0)
    localparam logic [11:0] MTVEC_ADDR     = 12'h305;
    localparam logic [31:0] MTVEC_RESET    = 32'h0000_0000;
    localparam logic [31:0] MTVEC_VALID    = 32'hffff_fffc;
    localparam logic [31:0] MTVEC_SW_WRITE = 32'hffff_fffc;
    localparam logic [31:0] MTVEC_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [29:0] base;      // 31:2, sw rw, hw none, reset 0
        logic [1:0]  zero_1_0;
    } mtvec_t;

    // mstatush: upper half of mstatus, nothing in it (0)
    localparam logic [11:0] MSTATUSH_ADDR     = 12'h310;
    localparam logic [31:0] MSTATUSH_RESET    = 32'h0000_0000;
    localparam logic [31:0] MSTATUSH_VALID    = 32'h0000_0000;
    localparam logic [31:0] MSTATUSH_SW_WRITE = 32'h0000_0000;
    localparam logic [31:0] MSTATUSH_CONST    = 32'h0000_0000;

    // ---- machine_trap_handling ----

    // mscratch: for the trap handler
    localparam logic [11:0] MSCRATCH_ADDR     = 12'h340;
    localparam logic [31:0] MSCRATCH_RESET    = 32'h0000_0000;
    localparam logic [31:0] MSCRATCH_VALID    = 32'hffff_ffff;
    localparam logic [31:0] MSCRATCH_SW_WRITE = 32'hffff_ffff;
    localparam logic [31:0] MSCRATCH_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [31:0] value;     // 31:0, sw rw, hw none, reset 0
    } mscratch_t;

    // mepc: pc of the trapping instruction (bits 1:0 read 0, no C extension)
    localparam logic [11:0] MEPC_ADDR     = 12'h341;
    localparam logic [31:0] MEPC_RESET    = 32'h0000_0000;
    localparam logic [31:0] MEPC_VALID    = 32'hffff_fffc;
    localparam logic [31:0] MEPC_SW_WRITE = 32'hffff_fffc;
    localparam logic [31:0] MEPC_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [29:0] pc;        // 31:2, sw rw, hw write, reset 0
        logic [1:0]  zero_1_0;
    } mepc_t;

    // mcause: the trap's cause; bit 31 for an interrupt
    localparam logic [11:0] MCAUSE_ADDR     = 12'h342;
    localparam logic [31:0] MCAUSE_RESET    = 32'h0000_0000;
    localparam logic [31:0] MCAUSE_VALID    = 32'hffff_ffff;
    localparam logic [31:0] MCAUSE_SW_WRITE = 32'hffff_ffff;
    localparam logic [31:0] MCAUSE_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [31:0] value;     // 31:0, sw rw, hw write, reset 0
    } mcause_t;

    // mtval: the trap's value (the address, the instruction)
    localparam logic [11:0] MTVAL_ADDR     = 12'h343;
    localparam logic [31:0] MTVAL_RESET    = 32'h0000_0000;
    localparam logic [31:0] MTVAL_VALID    = 32'hffff_ffff;
    localparam logic [31:0] MTVAL_SW_WRITE = 32'hffff_ffff;
    localparam logic [31:0] MTVAL_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [31:0] value;     // 31:0, sw rw, hw write, reset 0
    } mtval_t;

    // mip: pending interrupts; the interrupt controller clears MEIP
    localparam logic [11:0] MIP_ADDR     = 12'h344;
    localparam logic [31:0] MIP_RESET    = 32'h0000_0000;
    localparam logic [31:0] MIP_VALID    = 32'h0000_0800;
    localparam logic [31:0] MIP_SW_WRITE = 32'h0000_0000;
    localparam logic [31:0] MIP_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [19:0] zero_31_12;
        logic        meip;      // 11, sw ro, hw live, from meip
        logic [10:0] zero_10_0;
    } mip_t;

    // ---- machine_counters ----

    // mcycle: clocks since reset, low half; a CSR write wins over the count
    localparam logic [11:0] MCYCLE_ADDR     = 12'hb00;
    localparam logic [31:0] MCYCLE_RESET    = 32'h0000_0000;
    localparam logic [31:0] MCYCLE_VALID    = 32'hffff_ffff;
    localparam logic [31:0] MCYCLE_SW_WRITE = 32'hffff_ffff;
    localparam logic [31:0] MCYCLE_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [31:0] value;     // 31:0, sw rw, hw write, reset 0
    } mcycle_t;

    // minstret: completed instructions (not traps), low half
    localparam logic [11:0] MINSTRET_ADDR     = 12'hb02;
    localparam logic [31:0] MINSTRET_RESET    = 32'h0000_0000;
    localparam logic [31:0] MINSTRET_VALID    = 32'hffff_ffff;
    localparam logic [31:0] MINSTRET_SW_WRITE = 32'hffff_ffff;
    localparam logic [31:0] MINSTRET_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [31:0] value;     // 31:0, sw rw, hw write, reset 0
    } minstret_t;

    // mcycleh: mcycle, high half
    localparam logic [11:0] MCYCLEH_ADDR     = 12'hb80;
    localparam logic [31:0] MCYCLEH_RESET    = 32'h0000_0000;
    localparam logic [31:0] MCYCLEH_VALID    = 32'hffff_ffff;
    localparam logic [31:0] MCYCLEH_SW_WRITE = 32'hffff_ffff;
    localparam logic [31:0] MCYCLEH_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [31:0] value;     // 31:0, sw rw, hw write, reset 0
    } mcycleh_t;

    // minstreth: minstret, high half
    localparam logic [11:0] MINSTRETH_ADDR     = 12'hb82;
    localparam logic [31:0] MINSTRETH_RESET    = 32'h0000_0000;
    localparam logic [31:0] MINSTRETH_VALID    = 32'hffff_ffff;
    localparam logic [31:0] MINSTRETH_SW_WRITE = 32'hffff_ffff;
    localparam logic [31:0] MINSTRETH_CONST    = 32'h0000_0000;
    typedef struct packed {
        logic [31:0] value;     // 31:0, sw rw, hw write, reset 0
    } minstreth_t;

    /* verilator lint_on UNUSEDPARAM */

    // The CSRs a design keeps in flops or wires from signals: every field not constant.
    typedef struct packed {
        fcsr_t       fcsr;
        vxsat_t      vxsat;
        mhartid_t    mhartid;
        mstatus_t    mstatus;
        mie_t        mie;
        mtvec_t      mtvec;
        mscratch_t   mscratch;
        mepc_t       mepc;
        mcause_t     mcause;
        mtval_t      mtval;
        mip_t        mip;
        mcycle_t     mcycle;
        minstret_t   minstret;
        mcycleh_t    mcycleh;
        minstreth_t  minstreth;
    } csr_state_t;

    // A CSR read: whether a CSR is at the address, and its value (0 when none is).
    typedef struct packed {
        logic        exists;
        logic [31:0] value;
    } csr_value_t;

    // The value of the CSR at addr: its fields from s, its constant bits, 0 elsewhere.
    function automatic csr_value_t csr_read(logic [11:0] addr, csr_state_t s);
        csr_value_t r;

        r.exists = 1'b1;
        case (addr)
            FFLAGS_ADDR:     r.value = 32'({s.fcsr.fflags});
            FRM_ADDR:        r.value = 32'({s.fcsr.frm});
            FCSR_ADDR:       r.value = s.fcsr & FCSR_VALID;
            VXSAT_ADDR:      r.value = s.vxsat & VXSAT_VALID;
            CYCLE_ADDR:      r.value = s.mcycle & MCYCLE_VALID;
            TIME_ADDR:       r.value = s.mcycle & MCYCLE_VALID;
            INSTRET_ADDR:    r.value = s.minstret & MINSTRET_VALID;
            CYCLEH_ADDR:     r.value = s.mcycleh & MCYCLEH_VALID;
            TIMEH_ADDR:      r.value = s.mcycleh & MCYCLEH_VALID;
            INSTRETH_ADDR:   r.value = s.minstreth & MINSTRETH_VALID;
            MVENDORID_ADDR:  r.value = '0;
            MARCHID_ADDR:    r.value = '0;
            MIMPID_ADDR:     r.value = '0;
            MHARTID_ADDR:    r.value = s.mhartid & MHARTID_VALID;
            MSTATUS_ADDR:    r.value = (s.mstatus & MSTATUS_VALID & ~MSTATUS_CONST)
                                       | (MSTATUS_RESET & MSTATUS_CONST);
            MISA_ADDR:       r.value = MISA_RESET;
            MIE_ADDR:        r.value = s.mie & MIE_VALID;
            MTVEC_ADDR:      r.value = s.mtvec & MTVEC_VALID;
            MSTATUSH_ADDR:   r.value = '0;
            MSCRATCH_ADDR:   r.value = s.mscratch & MSCRATCH_VALID;
            MEPC_ADDR:       r.value = s.mepc & MEPC_VALID;
            MCAUSE_ADDR:     r.value = s.mcause & MCAUSE_VALID;
            MTVAL_ADDR:      r.value = s.mtval & MTVAL_VALID;
            MIP_ADDR:        r.value = s.mip & MIP_VALID;
            MCYCLE_ADDR:     r.value = s.mcycle & MCYCLE_VALID;
            MINSTRET_ADDR:   r.value = s.minstret & MINSTRET_VALID;
            MCYCLEH_ADDR:    r.value = s.mcycleh & MCYCLEH_VALID;
            MINSTRETH_ADDR:  r.value = s.minstreth & MINSTRETH_VALID;
            default: begin
                r.exists = 1'b0;
                r.value  = '0;
            end
        endcase
        return r;
    endfunction

    // The value of the CSR at addr after software writes wdata over old: its SW_WRITE bits
    // from wdata, the others kept (all of them for a CSR without rw bits, or none at addr).
    function automatic logic [31:0] csr_write_merge(logic [11:0] addr, logic [31:0] old,
                                                    logic [31:0] wdata);
        logic [31:0] mask;

        case (addr)
            FFLAGS_ADDR:     mask = FFLAGS_SW_WRITE;
            FRM_ADDR:        mask = FRM_SW_WRITE;
            FCSR_ADDR:       mask = FCSR_SW_WRITE;
            VXSAT_ADDR:      mask = VXSAT_SW_WRITE;
            MSTATUS_ADDR:    mask = MSTATUS_SW_WRITE;
            MIE_ADDR:        mask = MIE_SW_WRITE;
            MTVEC_ADDR:      mask = MTVEC_SW_WRITE;
            MSCRATCH_ADDR:   mask = MSCRATCH_SW_WRITE;
            MEPC_ADDR:       mask = MEPC_SW_WRITE;
            MCAUSE_ADDR:     mask = MCAUSE_SW_WRITE;
            MTVAL_ADDR:      mask = MTVAL_SW_WRITE;
            MCYCLE_ADDR:     mask = MCYCLE_SW_WRITE;
            MINSTRET_ADDR:   mask = MINSTRET_SW_WRITE;
            MCYCLEH_ADDR:    mask = MCYCLEH_SW_WRITE;
            MINSTRETH_ADDR:  mask = MINSTRETH_SW_WRITE;
            default:         mask = '0;
        endcase
        return (old & ~mask) | (wdata & mask);
    endfunction

endpackage
