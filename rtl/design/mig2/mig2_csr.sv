/* Mig2 CSRs: the Zicsr instructions, the Zicntr counters and the machine-mode trap CSRs.
 *
 * CSR instructions. A CSR instruction in EX reads the old value of the CSR at address
 * imm (rdata, the value for rd) and writes the new value when it completes (done=1):
 * CSRRW writes src, CSRRS old | src, CSRRC old & ~src. src is rs1_data, or for the I
 * forms (CSRRWI, CSRRSI, CSRRCI) the 5-bit immediate in the rs1 field. CSRRS and CSRRC
 * with rs1 = x0 (immediate 0) do not write, so they can read read-only CSRs.
 *
 * Illegal. illegal=1 when the CSR does not exist, or the instruction writes a read-only
 * CSR (address bits 11:10 are 3, as the spec says): nothing is written, and Mig2Control
 * makes it an illegal-instruction trap.
 *
 * The CSRs:
 * - mcycle, minstret: 64-bit counters, also read as cycle, instret and time (time is
 *   cycle, Mig2 has no real-time clock). mcycle counts every clock after reset, minstret
 *   every completed instruction (not traps); a CSR write wins over the count of its cycle.
 * - mscratch: read and write, for the trap handler.
 * - misa (RV32IM, writes ignored); mvendorid, marchid, mimpid, mhartid read 0.
 * - mstatus: MIE and MPIE; MPP reads 3 (machine mode only), other bits 0; mstatush 0.
 * - mtvec: direct mode only, bits 1:0 read 0; mepc: bits 1:0 read 0 (no C extension).
 * - mcause, mtval: written by traps, and by CSR instructions.
 * - mie, mip: read 0, writes ignored (no interrupts yet).
 *
 * Traps and MRET. A trap (trap.valid) sets mepc to pc, mcause and mtval from trap, MPIE
 * to MIE and MIE to 0; MRET, when it completes, sets MIE to MPIE and MPIE to 1. A
 * trapping instruction writes no CSR, so a trap, MRET and a CSR write never meet.
 *
 * Mig2Core instantiates it in EX, for the instruction in EX. From Mig2Control: done (the
 * instruction completes) and trap (it faults). To Mig2Control: illegal, and csr (mtvec
 * and mepc: where traps and MRET go). rdata is rd's value (rd_src RD_CSR).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig2Csr import Mig2Pkg::*, RiscvPkg::*, RiscvCsrPkg::*; (
    input  wire      clk,
    input  wire      rst_n,      // synchronous reset, active low
    input  wire      valid,      // instruction in EX is valid
    input  wire      done,       // instruction in EX completes: CSR write, minstret
    // Only sys, funct3, rs1 and imm are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t dec,        // the instruction taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t    rs1_data,
    input  iaddr_t   pc,         // address of the instruction in EX
    input  trap_t    trap,       // the instruction in EX traps
    output word_t    rdata,      // old value of the CSR
    output wire      illegal,    // CSR does not exist, or write to a read-only CSR
    output csr_t     csr         // mtvec and mepc, for traps and MRET
);
    localparam word_t MISA = 32'h4000_1100;    // MXL=1: 32-bit; extensions I, M

    logic [11:0] addr;          // CSR address (immediate of the CSR instruction)
    assign addr = dec.imm[11:0];

    dword_t mcycle;         // also cycle and time
    dword_t minstret;       // also instret
    word_t  mscratch;
    logic   mstatus_mie;    // machine interrupt enable
    logic   mstatus_mpie;   // MIE before the trap
    iaddr_t mtvec;
    iaddr_t mepc;
    word_t  mcause;
    word_t  mtval;
    word_t  mstatus;

    logic  imm_form;    // CSRRWI, CSRRSI, CSRRCI
    logic  writes;      // the instruction writes the CSR
    logic  exists;      // the CSR at addr exists
    logic  read_only;   // addr marks the CSR read-only
    word_t old;         // value of the CSR before the instruction
    word_t src;         // operand: rs1, or the immediate of the I forms
    word_t new_value;   // value written to the CSR
    logic  we;          // the CSR is written at the end of this cycle

    assign imm_form  = dec.funct3 == F3_CSRRWI || dec.funct3 == F3_CSRRSI ||
                       dec.funct3 == F3_CSRRCI;
    // rs1 field: register, or immediate of the I forms.
    assign src       = imm_form ? {{(WIDTH-REG_ID_WIDTH){1'b0}}, dec.rs1} : rs1_data;
    assign writes    = dec.funct3 == F3_CSRRW || dec.funct3 == F3_CSRRWI || dec.rs1 != '0;
    assign read_only = addr[11:10] == 2'b11;

    // mstatus: MPP (12:11) = 3, MPIE (7), MIE (3).
    assign mstatus = {{(WIDTH-13){1'b0}}, 2'b11, 3'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};

    // Read: the old value of the CSR at addr.
    always_comb begin
        exists = 1'b1;
        case (addr)
            CSR_CYCLE, CSR_TIME, CSR_MCYCLE:        old = mcycle.lo;
            CSR_CYCLEH, CSR_TIMEH, CSR_MCYCLEH:     old = mcycle.hi;
            CSR_INSTRET, CSR_MINSTRET:              old = minstret.lo;
            CSR_INSTRETH, CSR_MINSTRETH:            old = minstret.hi;
            CSR_MSCRATCH:                           old = mscratch;
            CSR_MSTATUS:                            old = mstatus;
            CSR_MTVEC:                              old = {mtvec, {IADDR_START{1'b0}}};
            CSR_MEPC:                               old = {mepc, {IADDR_START{1'b0}}};
            CSR_MCAUSE:                             old = mcause;
            CSR_MTVAL:                              old = mtval;
            CSR_MSTATUSH, CSR_MIE, CSR_MIP:         old = '0;
            CSR_MISA:                               old = MISA;
            CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID,
            CSR_MHARTID:                            old = '0;
            default: begin                          old = '0; exists = 1'b0; end
        endcase
    end

    assign rdata   = old;
    assign illegal = valid && dec.sys.csr && (!exists || (writes && read_only));

    // Write: the new value, at the end of the cycle when the instruction completes.
    always_comb
        case (dec.funct3)
            F3_CSRRS, F3_CSRRSI: new_value = old | src;
            F3_CSRRC, F3_CSRRCI: new_value = old & ~src;
            default:             new_value = src;       // CSRRW, CSRRWI
        endcase

    // done=1 means valid and not illegal.
    assign we = done && dec.sys.csr && writes;

    // Bits of new_value: MIE and MPIE of mstatus, the address of mtvec and mepc.
    logic   new_mie;
    logic   new_mpie;
    iaddr_t new_iaddr;      // new value of mtvec, mepc without bits 1:0
    logic   mret;           // MRET completes
    assign new_mie   = new_value[3];
    assign new_mpie  = new_value[7];
    assign new_iaddr = new_value[WIDTH-1:IADDR_START];
    assign mret      = done && dec.sys.mret;

    // Counters.
    always_ff @(posedge clk)
        if (!rst_n)                         mcycle <= '0;
        else if (we && addr == CSR_MCYCLE)  mcycle.lo <= new_value;
        else if (we && addr == CSR_MCYCLEH) mcycle.hi <= new_value;
        else                                mcycle <= mcycle + 1'b1;

    always_ff @(posedge clk)
        if (!rst_n)                           minstret <= '0;
        else if (we && addr == CSR_MINSTRET)  minstret.lo <= new_value;
        else if (we && addr == CSR_MINSTRETH) minstret.hi <= new_value;
        else if (done)                        minstret <= minstret + 1'b1;

    // mscratch.
    always_ff @(posedge clk)
        if (!rst_n)                          mscratch <= '0;
        else if (we && addr == CSR_MSCRATCH) mscratch <= new_value;

    // mstatus: a trapping instruction writes no CSR, so trap, MRET and CSR writes never
    // meet.
    always_ff @(posedge clk)
        if (!rst_n) begin
            mstatus_mie  <= 1'b0;
            mstatus_mpie <= 1'b0;
        end else if (trap.valid) begin
            mstatus_mpie <= mstatus_mie;
            mstatus_mie  <= 1'b0;
        end else if (mret) begin
            mstatus_mie  <= mstatus_mpie;
            mstatus_mpie <= 1'b1;
        end else if (we && addr == CSR_MSTATUS) begin
            mstatus_mie  <= new_mie;
            mstatus_mpie <= new_mpie;
        end

    // mepc, mcause, mtval: set by a trap, or written by CSR instructions.
    always_ff @(posedge clk)
        if (!rst_n) begin
            mepc   <= '0;
            mcause <= '0;
            mtval  <= '0;
        end else if (trap.valid) begin
            mepc   <= pc;
            mcause <= {{(WIDTH-$bits(excp_code_t)){1'b0}}, trap.cause};
            mtval  <= trap.tval;
        end else if (we && addr == CSR_MEPC)
            mepc   <= new_iaddr;
        else if (we && addr == CSR_MCAUSE)
            mcause <= new_value;
        else if (we && addr == CSR_MTVAL)
            mtval  <= new_value;

    // mtvec.
    always_ff @(posedge clk)
        if (!rst_n)                       mtvec <= '0;
        else if (we && addr == CSR_MTVEC) mtvec <= new_iaddr;

    assign csr.mtvec = mtvec;
    assign csr.mepc  = mepc;

endmodule
