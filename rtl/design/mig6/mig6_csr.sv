/* Mig6 CSRs: the Zicsr instructions, the Zicntr counters and the machine-mode trap CSRs.
 *
 * CSR instructions. A CSR instruction in EX reads the old value of the CSR at address
 * imm (rdata, the value for rd) and writes the new value when it completes (done=1):
 * CSRRW writes src, CSRRS old | src, CSRRC old & ~src. src is rs1_data, or for the I
 * forms (CSRRWI, CSRRSI, CSRRCI) the 5-bit immediate in the rs1 field. CSRRS and CSRRC
 * with rs1 = x0 (immediate 0) do not write, so they can read read-only CSRs.
 *
 * Illegal. illegal=1 when the CSR does not exist, or the instruction writes a read-only
 * CSR (address bits 11:10 are 3, as the spec says): nothing is written, and Mig6Control
 * makes it an illegal-instruction trap.
 *
 * Mig6CsrPkg, generated from cfg/mig6_csr.yaml (tools/csr_gen.py), has the facts of every
 * CSR: its address, reset value, bits and the bits software writes, and a struct of its
 * fields. Here the flops (the fields that are not constant) and the special behavior
 * (counting, traps, MRET, flags) stay by hand; the package's csr_read gives a CSR's value
 * from them (csr_state_t; constant bits from the YAML, the others 0), and csr_write_merge
 * keeps a write to the bits software writes (w, seen as any CSR's struct).
 *
 *   flops, meip, HART_ID --> state --> csr_read (addr) --> old, exists
 *   old, src, funct3 --> new_value --> csr_write_merge (addr) --> w --> the flops
 *
 * The CSRs:
 * - mcycle, minstret: 64-bit counters, also read as cycle, instret and time (time is
 *   cycle, Mig6 has no real-time clock). mcycle counts every clock after reset, minstret
 *   every completed instruction (not traps); a CSR write wins over the count of its cycle.
 * - mscratch: read and write, for the trap handler.
 * - misa (RV32IMA, writes ignored: Zbb has no bit, B stands for the whole extension);
 *   mvendorid, marchid, mimpid read 0; mhartid reads HART_ID, the hart's ID (the PE's in
 *   Mig6, Mig6Pe); mnodeid, Mig6's own (a custom read-only CSR), reads MY_PE_GRID_X and
 *   MY_PE_GRID_Y, the PE's node in the mesh.
 * - mstatus: MIE and MPIE; MPP reads 3 (machine mode only), other bits 0; mstatush 0.
 * - mtvec: direct mode only, bits 1:0 read 0; mepc: bits 1:0 read 0 (no C extension).
 * - mcause, mtval: written by traps, and by CSR instructions.
 * - mie: MEIE (bit 11), read and write, other bits 0; mip: MEIP (bit 11) is meip, the
 *   machine external interrupt, read-only (the interrupt controller clears it), other
 *   bits 0.
 * - fcsr (Zfinx: F on the x registers): frm in bits 7:5 and fflags in 4:0, the other bits
 *   0; frm and fflags alone are views of the same flops. frm takes any value (an F
 *   instruction that rounds by an invalid frm is illegal: the FPU's part); an F
 *   instruction that completes ORs its flags (fp_flags) into fflags. misa.F and
 *   mstatus.FS stay 0 (Zfinx: no FP registers to save), so fcsr is always accessible.
 *
 * Interrupts. csr.irq = MEIP && MEIE && MIE: an interrupt is pending and enabled; from
 * flops and meip only, so Mig6Control takes it on the instruction after a CSR write or
 * MRET that enables it. csr.pending = MEIP && MEIE, whatever MIE: what wakes a WFI (the
 * spec: an interrupt pending and enabled in mie). An interrupt trap sets the interrupt
 * bit of mcause.
 *
 * Traps and MRET. A trap (trap.valid) sets mepc to pc, mcause and mtval from trap, MPIE
 * to MIE and MIE to 0; MRET, when it completes, sets MIE to MPIE and MPIE to 1. A
 * trapping instruction writes no CSR, so a trap, MRET and a CSR write never meet.
 *
 * Mig6Core instantiates it in EX, for the instruction in EX. From Mig6Control: done (the
 * instruction completes) and trap (it faults). To Mig6Control: illegal, and csr (mtvec
 * and mepc: where traps and MRET go). rdata is rd's value (rd_src RD_CSR). From the FPU:
 * fp_flags; to it: frm.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig6Csr import Mig6Pkg::*, RiscvPkg::*, Mig6CsrPkg::*; #(
    parameter word_t      HART_ID      = '0,    // the hart's ID: mhartid
    parameter logic [7:0] MY_PE_GRID_X = '0,    // the PE's node in the mesh: mnodeid
    parameter logic [7:0] MY_PE_GRID_Y = '0
)(
    input  wire      clk,
    input  wire      rst_n,      // synchronous reset, active low
    input  wire      valid,      // instruction in EX is valid
    input  wire      done,       // instruction in EX completes: CSR write, minstret
    // Only sys, fp.en, funct3, rs1 and imm are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t dec,        // the instruction taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t    rs1_data,
    input  iaddr_t   pc,         // address of the instruction in EX
    input  wire      meip,       // machine external interrupt pending (mip.MEIP)
    input  trap_t    trap,       // the instruction in EX traps
    output word_t    rdata,      // old value of the CSR
    output wire      illegal,    // CSR does not exist, or write to a read-only CSR
    output csr_t     csr,        // mtvec and mepc, for traps and MRET
    input  FpPkg::flags_t fp_flags,    // the flags of the F instruction in EX (Zfinx)
    output funct3_t  frm         // rounding mode for FRM_DYN (any value: the FPU checks)
);
    // Reset values of the flops, from the YAML (Mig6CsrPkg).
    localparam mstatus_t R_MSTATUS = MSTATUS_RESET;
    localparam mie_t     R_MIE     = MIE_RESET;
    localparam mtvec_t   R_MTVEC   = MTVEC_RESET;
    localparam mepc_t    R_MEPC    = MEPC_RESET;
    localparam fcsr_t    R_FCSR    = FCSR_RESET;

    logic [11:0] addr;          // CSR address (immediate of the CSR instruction)
    assign addr = dec.imm[11:0];

    dword_t mcycle;         // also cycle and time
    dword_t minstret;       // also instret
    word_t  mscratch;
    logic   mstatus_mie;    // machine interrupt enable
    logic   mstatus_mpie;   // MIE before the trap
    logic   mie_meie;       // machine external interrupt enable (mie.MEIE)
    iaddr_t mtvec;
    iaddr_t mepc;
    word_t  mcause;
    word_t  mtval;
    funct3_t       frm_q;     // fcsr.frm
    FpPkg::flags_t fflags;    // fcsr.fflags

    logic       imm_form;   // CSRRWI, CSRRSI, CSRRCI
    logic       writes;     // the instruction writes the CSR
    logic       read_only;  // addr marks the CSR read-only
    csr_state_t state;      // every CSR's fields that are not constant
    csr_value_t read;       // the CSR at addr: exists, its value
    word_t      old;        // value of the CSR before the instruction
    word_t      src;        // operand: rs1, or the immediate of the I forms
    word_t      new_value;  // value the instruction writes
    // A write as any CSR's struct; each flop reads its own field.
    /* verilator lint_off UNUSEDSIGNAL */
    csr_word_t  w;          // new_value in the bits software writes, the others kept
    /* verilator lint_on UNUSEDSIGNAL */
    logic       we;         // the CSR is written at the end of this cycle
    logic       mret;       // MRET completes

    assign imm_form  = dec.funct3 == F3_CSRRWI || dec.funct3 == F3_CSRRSI ||
                       dec.funct3 == F3_CSRRCI;
    // rs1 field: register, or immediate of the I forms.
    assign src       = imm_form ? {{(WIDTH-REG_ID_WIDTH){1'b0}}, dec.rs1} : rs1_data;
    assign writes    = dec.funct3 == F3_CSRRW || dec.funct3 == F3_CSRRWI || dec.rs1 != '0;
    assign read_only = csr_read_only(addr);

    // Read: every CSR's fields from the flops and signals, the one at addr by csr_read.
    always_comb begin
        state                 = '0;
        state.fcsr.frm        = frm_q;
        state.fcsr.fflags     = fflags;
        state.mhartid.id      = HART_ID;
        state.mnodeid.x       = MY_PE_GRID_X;
        state.mnodeid.y       = MY_PE_GRID_Y;
        state.mstatus.mie     = mstatus_mie;
        state.mstatus.mpie    = mstatus_mpie;
        state.mie.meie        = mie_meie;
        state.mtvec.base      = mtvec;
        state.mscratch.value  = mscratch;
        state.mepc.pc         = mepc;
        state.mcause.value    = mcause;
        state.mtval.value     = mtval;
        state.mip.meip        = meip;
        state.mcycle.value    = mcycle.lo;
        state.mcycleh.value   = mcycle.hi;
        state.minstret.value  = minstret.lo;
        state.minstreth.value = minstret.hi;
    end

    assign read    = csr_read(addr, state);
    assign old     = read.value;
    assign rdata   = old;
    assign illegal = valid && dec.sys.csr && (!read.exists || (writes && read_only));

    // Write: the new value, at the end of the cycle when the instruction completes, in the
    // bits software writes.
    always_comb
        case (dec.funct3)
            F3_CSRRS, F3_CSRRSI: new_value = old | src;
            F3_CSRRC, F3_CSRRCI: new_value = old & ~src;
            default:             new_value = src;       // CSRRW, CSRRWI
        endcase

    assign w    = csr_write_merge(addr, old, new_value);
    // done=1 means valid and not illegal.
    assign we   = done && dec.sys.csr && writes;
    assign mret = done && dec.sys.mret;

    // Counters.
    always_ff @(posedge clk)
        if (!rst_n)                          mcycle <= {MCYCLEH_RESET, MCYCLE_RESET};
        else if (we && addr == MCYCLE_ADDR)  mcycle.lo <= w.mcycle.value;
        else if (we && addr == MCYCLEH_ADDR) mcycle.hi <= w.mcycleh.value;
        else                                 mcycle <= mcycle + 1'b1;

    always_ff @(posedge clk)
        if (!rst_n)                            minstret <= {MINSTRETH_RESET, MINSTRET_RESET};
        else if (we && addr == MINSTRET_ADDR)  minstret.lo <= w.minstret.value;
        else if (we && addr == MINSTRETH_ADDR) minstret.hi <= w.minstreth.value;
        else if (done)                         minstret <= minstret + 1'b1;

    // mscratch.
    always_ff @(posedge clk)
        if (!rst_n)                           mscratch <= MSCRATCH_RESET;
        else if (we && addr == MSCRATCH_ADDR) mscratch <= w.mscratch.value;

    // mstatus: a trapping instruction writes no CSR, so trap, MRET and CSR writes never
    // meet.
    always_ff @(posedge clk)
        if (!rst_n) begin
            mstatus_mie  <= R_MSTATUS.mie;
            mstatus_mpie <= R_MSTATUS.mpie;
        end else if (trap.valid) begin
            mstatus_mpie <= mstatus_mie;
            mstatus_mie  <= 1'b0;
        end else if (mret) begin
            mstatus_mie  <= mstatus_mpie;
            mstatus_mpie <= 1'b1;
        end else if (we && addr == MSTATUS_ADDR) begin
            mstatus_mie  <= w.mstatus.mie;
            mstatus_mpie <= w.mstatus.mpie;
        end

    // mepc, mcause, mtval: set by a trap, or written by CSR instructions.
    always_ff @(posedge clk)
        if (!rst_n) begin
            mepc   <= R_MEPC.pc;
            mcause <= MCAUSE_RESET;
            mtval  <= MTVAL_RESET;
        end else if (trap.valid) begin
            mepc   <= pc;
            mcause <= {trap.irq, {(WIDTH-1-$bits(excp_code_t)){1'b0}}, trap.cause};
            mtval  <= trap.tval;
        end else if (we && addr == MEPC_ADDR)
            mepc   <= w.mepc.pc;
        else if (we && addr == MCAUSE_ADDR)
            mcause <= w.mcause.value;
        else if (we && addr == MTVAL_ADDR)
            mtval  <= w.mtval.value;

    // mie: MEIE; the other interrupts do not exist. mip: MEIP is meip, read-only.
    always_ff @(posedge clk)
        if (!rst_n)                      mie_meie <= R_MIE.meie;
        else if (we && addr == MIE_ADDR) mie_meie <= w.mie.meie;

    // mtvec.
    always_ff @(posedge clk)
        if (!rst_n)                        mtvec <= R_MTVEC.base;
        else if (we && addr == MTVEC_ADDR) mtvec <= w.mtvec.base;

    // @kb: rtl/design/mig3/fp_decode
    // fcsr: frm and fflags, also written alone (frm, fflags: views packed from bit 0); an F
    // instruction that completes ORs its flags into fflags (it is no CSR instruction: the
    // two never meet).
    always_ff @(posedge clk)
        if (!rst_n) begin
            frm_q  <= R_FCSR.frm;
            fflags <= R_FCSR.fflags;
        end else if (we && addr == FCSR_ADDR) begin
            frm_q  <= w.fcsr.frm;
            fflags <= w.fcsr.fflags;
        end else if (we && addr == FRM_ADDR)
            frm_q  <= w.raw[$bits(frm_q)-1:0];
        else if (we && addr == FFLAGS_ADDR)
            fflags <= w.raw[$bits(fflags)-1:0];
        else if (done && dec.fp.en)
            fflags <= fflags | fp_flags;

    assign frm       = frm_q;
    assign csr.mtvec = mtvec;
    assign csr.mepc  = mepc;
    assign csr.irq     = meip && mie_meie && mstatus_mie;
    assign csr.pending = meip && mie_meie;

endmodule
