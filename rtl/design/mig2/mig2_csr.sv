/* Mig2 CSRs: Zicsr instructions on the CSRs of Mig2, the Zicntr counters and the
 * machine-mode trap CSRs.
 *
 * A CSR instruction in EX reads the old value of the CSR at address imm (rdata, the
 * value for rd) and writes the new one when it completes (done=1): CSRRW writes src,
 * CSRRS old | src, CSRRC old & ~src; src is rs1_data, or for the I forms the 5-bit
 * immediate in the rs1 field. CSRRS and CSRRC with rs1 = x0 (immediate 0) do not
 * write, so they can read read-only CSRs.
 * illegal=1 when the CSR does not exist, or the instruction writes a read-only CSR
 * (address bits 11:10 are 3, as the spec says): nothing is written, the instruction
 * must not complete.
 * CSRs: mcycle and minstret (64-bit; also read as cycle and instret; time is cycle,
 * Mig2 has no real-time clock), mscratch, misa (RV32IM, writes are ignored), mvendorid,
 * marchid, mimpid, mhartid (0). mcycle counts every clock after reset, minstret every
 * completed instruction (not traps); a CSR write wins over the count of its cycle.
 * Traps: mstatus (MIE, MPIE; MPP reads 3, machine mode only; other bits 0), mstatush (0),
 * mtvec (direct mode only: bits 1:0 read 0), mepc (bits 1:0 read 0, no compressed
 * instructions), mcause, mtval, mie and mip (0, no interrupts yet; writes are ignored).
 * A trap (trap.valid) sets mepc to pc, mcause and mtval from trap, MPIE to MIE and MIE
 * to 0; MRET when it completes sets MIE to MPIE and MPIE to 1. csr has mtvec and mepc.
 */
module Mig2Csr import Mig2Pkg::*, RiscvPkg::*, RiscvCsrPkg::*; (
    input  wire              clk,
    input  wire              rst_n,      // synchronous reset, active low
    input  wire              valid,      // instruction in EX is valid
    input  wire              done,       // instruction in EX completes: CSR write, minstret
    // Only kind, funct3, rs1 and imm are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t         dec,
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t            rs1_data,
    input  logic [WIDTH-1:IADDR_START] pc, // iaddr_t: address of the instruction in EX
    input  trap_t            trap,       // the instruction in EX traps
    output word_t            rdata,      // old value of the CSR
    output wire              illegal,    // CSR does not exist, or write to a read-only CSR
    output csr_t             csr         // mtvec and mepc, for traps and MRET
);
    localparam word_t MISA = 32'h4000_1100;    // MXL=1: 32-bit; extensions I, M

    // Fields of dec, selected with assign: Icarus warns about selects in always_comb.
    kind_t      kind;
    logic [2:0] funct3;
    reg_id_t    rs1;            // register, or immediate of the I forms
    logic [11:0] addr;          // CSR address
    assign kind   = dec.kind;
    assign funct3 = dec.funct3;
    assign rs1    = dec.rs1;
    assign addr   = dec.imm[11:0];

    logic [63:0] mcycle;
    logic [63:0] minstret;
    word_t       mscratch;
    logic        mstatus_mie;   // machine interrupt enable
    logic        mstatus_mpie;  // MIE before the trap
    iaddr_t      mtvec;
    iaddr_t      mepc;
    word_t       mcause;
    word_t       mtval;
    word_t       mstatus;
    word_t       mcycle_lo;
    word_t       mcycle_hi;
    word_t       minstret_lo;
    word_t       minstret_hi;
    assign mcycle_lo   = mcycle[31:0];
    assign mcycle_hi   = mcycle[63:32];
    assign minstret_lo = minstret[31:0];
    assign minstret_hi = minstret[63:32];

    logic  imm_form;    // CSRRWI, CSRRSI, CSRRCI
    logic  writes;      // the instruction writes the CSR
    logic  exists;
    logic  read_only;
    word_t old;
    word_t src;
    word_t new_value;
    logic  we;

    assign imm_form  = funct3 == F3_CSRRWI || funct3 == F3_CSRRSI || funct3 == F3_CSRRCI;
    assign src       = imm_form ? {{(WIDTH-REG_ID_WIDTH){1'b0}}, rs1} : rs1_data;
    assign writes    = funct3 == F3_CSRRW || funct3 == F3_CSRRWI || rs1 != '0;
    assign read_only = addr[11:10] == 2'b11;

    // mstatus: MPP (12:11) = 3, MPIE (7), MIE (3).
    assign mstatus = {{(WIDTH-13){1'b0}}, 2'b11, 3'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};

    always_comb begin
        exists = 1'b1;
        case (addr)
            CSR_CYCLE, CSR_TIME, CSR_MCYCLE:        old = mcycle_lo;
            CSR_CYCLEH, CSR_TIMEH, CSR_MCYCLEH:     old = mcycle_hi;
            CSR_INSTRET, CSR_MINSTRET:              old = minstret_lo;
            CSR_INSTRETH, CSR_MINSTRETH:            old = minstret_hi;
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
    assign illegal = valid && kind == KIND_CSR && (!exists || (writes && read_only));

    always_comb
        case (funct3)
            F3_CSRRS, F3_CSRRSI: new_value = old | src;
            F3_CSRRC, F3_CSRRCI: new_value = old & ~src;
            default:             new_value = src;       // CSRRW, CSRRWI
        endcase

    // done=1 means valid and not illegal.
    assign we = done && kind == KIND_CSR && writes;

    // Fields of new_value and trap, selected with assign (Icarus, see above).
    logic   new_mie;
    logic   new_mpie;
    iaddr_t new_iaddr;      // new value of mtvec, mepc without bits 1:0
    logic   trap_valid;
    logic [4:0] trap_cause;
    word_t  trap_tval;
    logic   mret;           // MRET completes
    assign new_mie    = new_value[3];
    assign new_mpie   = new_value[7];
    assign new_iaddr  = new_value[WIDTH-1:IADDR_START];
    assign trap_valid = trap.valid;
    assign trap_cause = trap.cause;
    assign trap_tval  = trap.tval;
    assign mret       = done && kind == KIND_MRET;

    always_ff @(posedge clk)
        if (!rst_n)                         mcycle <= '0;
        else if (we && addr == CSR_MCYCLE)  mcycle <= {mcycle_hi, new_value};
        else if (we && addr == CSR_MCYCLEH) mcycle <= {new_value, mcycle_lo};
        else                                mcycle <= mcycle + 1'b1;

    always_ff @(posedge clk)
        if (!rst_n)                           minstret <= '0;
        else if (we && addr == CSR_MINSTRET)  minstret <= {minstret_hi, new_value};
        else if (we && addr == CSR_MINSTRETH) minstret <= {new_value, minstret_lo};
        else if (done)                        minstret <= minstret + 1'b1;

    always_ff @(posedge clk)
        if (!rst_n)                          mscratch <= '0;
        else if (we && addr == CSR_MSCRATCH) mscratch <= new_value;

    // A trapping instruction writes no CSR, so trap, MRET and CSR writes never meet.
    always_ff @(posedge clk)
        if (!rst_n) begin
            mstatus_mie  <= 1'b0;
            mstatus_mpie <= 1'b0;
        end else if (trap_valid) begin
            mstatus_mpie <= mstatus_mie;
            mstatus_mie  <= 1'b0;
        end else if (mret) begin
            mstatus_mie  <= mstatus_mpie;
            mstatus_mpie <= 1'b1;
        end else if (we && addr == CSR_MSTATUS) begin
            mstatus_mie  <= new_mie;
            mstatus_mpie <= new_mpie;
        end

    always_ff @(posedge clk)
        if (!rst_n) begin
            mepc   <= '0;
            mcause <= '0;
            mtval  <= '0;
        end else if (trap_valid) begin
            mepc   <= pc;
            mcause <= {{(WIDTH-5){1'b0}}, trap_cause};
            mtval  <= trap_tval;
        end else if (we && addr == CSR_MEPC)
            mepc   <= new_iaddr;
        else if (we && addr == CSR_MCAUSE)
            mcause <= new_value;
        else if (we && addr == CSR_MTVAL)
            mtval  <= new_value;

    always_ff @(posedge clk)
        if (!rst_n)                       mtvec <= '0;
        else if (we && addr == CSR_MTVEC) mtvec <= new_iaddr;

    assign csr.mtvec = mtvec;
    assign csr.mepc  = mepc;

endmodule
