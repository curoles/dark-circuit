/* Mig1 CSRs: Zicsr instructions on the CSRs of Mig1, and the Zicntr counters.
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
 * Mig1 has no real-time clock), mscratch, misa (RV32I, writes are ignored), mvendorid,
 * marchid, mimpid, mhartid (0). mcycle counts every clock after reset, minstret every
 * completed instruction (not traps); a CSR write wins over the count of its cycle.
 */
module Mig1Csr import Mig1Pkg::*, RiscvPkg::*, RiscvCsrPkg::*; (
    input  wire              clk,
    input  wire              rst_n,      // synchronous reset, active low
    input  wire              valid,      // instruction in EX is valid
    input  wire              done,       // instruction in EX completes: CSR write, minstret
    // Only kind, funct3, rs1 and imm are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t         dec,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [WIDTH-1:0] rs1_data,   // word_t, see Mig1Pkg about ports
    output logic [WIDTH-1:0] rdata,      // old value of the CSR
    output wire              illegal     // CSR does not exist, or write to a read-only CSR
);
    localparam word_t MISA = 32'h4000_0100;    // MXL=1: 32-bit; extension I

    // Fields of dec, selected with assign: Icarus warns about selects in always_comb.
    kind_t      kind;
    logic [2:0] funct3;
    reg_addr_t  rs1;            // register, or immediate of the I forms
    logic [11:0] addr;          // CSR address
    assign kind   = dec.kind;
    assign funct3 = dec.funct3;
    assign rs1    = dec.rs1;
    assign addr   = dec.imm[11:0];

    logic [63:0] mcycle;
    logic [63:0] minstret;
    word_t       mscratch;
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
    assign src       = imm_form ? {{(WIDTH-REG_ADDR_WIDTH){1'b0}}, rs1} : rs1_data;
    assign writes    = funct3 == F3_CSRRW || funct3 == F3_CSRRWI || rs1 != '0;
    assign read_only = addr[11:10] == 2'b11;

    always_comb begin
        exists = 1'b1;
        case (addr)
            CSR_CYCLE, CSR_TIME, CSR_MCYCLE:        old = mcycle_lo;
            CSR_CYCLEH, CSR_TIMEH, CSR_MCYCLEH:     old = mcycle_hi;
            CSR_INSTRET, CSR_MINSTRET:              old = minstret_lo;
            CSR_INSTRETH, CSR_MINSTRETH:            old = minstret_hi;
            CSR_MSCRATCH:                           old = mscratch;
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

endmodule
