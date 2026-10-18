/* Constants and port types of Mig1 RISC-V CPU.
 *
 * Port groups of Mig1Core are packed structs, one struct per direction:
 * <group>_req_t goes from the requester, <group>_rsp_t comes back.
 * Two rules because of Icarus 11 bugs:
 * - modules import this package in their header, `module X import Mig1Pkg::*; #(`:
 *   Icarus crashes (assert in elab_type.cc) when the structs are used only as
 *   Mig1Pkg::<type> and no module imports the package;
 * - a port of a vector type (word_t, insn_t, iaddr_t, ...) is written with its range,
 *   `input logic [INSN_WIDTH-1:0] insn`: Icarus can not bind the range of the typedef
 *   in a port ("Unable to bind parameter"); structs and internal signals may use them.
 * Instruction and data addresses on ports are word addresses (iaddr_t, daddr_t),
 * register values are byte addresses like software sees them.
 */
package Mig1Pkg;

    // ISA facts.
    localparam WIDTH          = 32;                 // register and data width (RISC-V XLEN)
    localparam INSN_WIDTH     = 32;                 // instruction width, 32 also for RV64
    localparam STRB_WIDTH     = WIDTH / 8;          // bytes in data word
    localparam REG_ADDR_WIDTH = 5;                  // 32 registers x0..x31
    localparam IADDR_START    = 2;                  // instructions are 4-byte aligned (1 with C extension)
    localparam DADDR_START    = $clog2(STRB_WIDTH); // data words are STRB_WIDTH-byte aligned

    // Constants below are for all modules and testbenches; a design with one
    // module as top, like a unit test, uses only some of them.
    /* verilator lint_off UNUSEDPARAM */

    // Configuration of Mig1 from cfg/mig1_config.yaml (Mig1ConfigPkg),
    // defaults of module parameters RST_ADDR and MEM_ADDR_WIDTH.
    localparam MIG1_RST_ADDR       = Mig1ConfigPkg::RST_ADDR;        // PC after reset, byte address
    localparam MIG1_MEM_ADDR_WIDTH = Mig1ConfigPkg::MEM_ADDR_WIDTH;  // Mig1Cpu: imem and dmem size

    typedef logic [WIDTH-1:0]           word_t;      // register value, data word
    typedef logic [INSN_WIDTH-1:0]      insn_t;      // instruction
    typedef logic [WIDTH-1:IADDR_START] iaddr_t;     // instruction address, word address
    typedef logic [WIDTH-1:DADDR_START] daddr_t;     // data address, word address
    typedef logic [STRB_WIDTH-1:0]      strb_t;      // byte enables of data word
    typedef logic [REG_ADDR_WIDTH-1:0]  reg_addr_t;  // register number

    // Instructions with fixed encoding.
    localparam insn_t INSN_EBREAK = 32'h0010_0073;

    /* verilator lint_on UNUSEDPARAM */

    // Instruction fetch: rsp.data is the word at req.addr 1 clock after req.en=1.
    typedef struct packed {
        logic   en;
        iaddr_t addr;
    } imem_req_t;

    typedef struct packed {
        insn_t  data;
    } imem_rsp_t;

    // Data: rsp.rd_data comes 1 clock after req.rd_en=1;
    // req.wr_en=1 writes bytes of wr_data with wr_strb=1, see SimRAM.
    typedef struct packed {
        logic   rd_en;
        logic   wr_en;
        daddr_t addr;
        word_t  wr_data;
        strb_t  wr_strb;
    } dmem_req_t;

    typedef struct packed {
        word_t  rd_data;
    } dmem_rsp_t;

    // Retire: one entry per retired instruction, RVFI (riscv-formal) fields and names.
    // Unlike other ports, addresses are byte addresses, as in RVFI. A register or
    // memory field that the instruction does not use is 0. Memory is RVFI "aligned
    // memory": mem_addr is word aligned, masks select the bytes of mem_rdata/mem_wdata.
    // RVFI fields that are constant for Mig1 are not here: intr=0, mode=3 (M), ixl=1.
    typedef struct packed {
        logic        valid;      // an instruction retires: it completes, or traps
        logic [63:0] order;      // index of the retired instruction: 0, 1, 2, ...
        insn_t       insn;
        logic        trap;       // the instruction faulted: no register or memory write
        word_t       pc_rdata;   // address of the instruction
        word_t       pc_wdata;   // address of the next instruction
        reg_addr_t   rs1_addr;   // registers read, 0 when not read
        word_t       rs1_rdata;
        reg_addr_t   rs2_addr;
        word_t       rs2_rdata;
        reg_addr_t   rd_addr;    // register written, 0 when none (also for x0)
        word_t       rd_wdata;
        word_t       mem_addr;   // load or store: word address as byte address
        strb_t       mem_rmask;  // bytes read
        strb_t       mem_wmask;  // bytes written
        word_t       mem_rdata;  // word read
        word_t       mem_wdata;  // word written, bytes of mem_wmask
    } retire_t;

    // Debug, used while the core is halted.
    typedef struct packed {
        reg_addr_t reg_addr;  // register to read or write
        logic      reg_wr;    // 1: write reg_wdata into reg_addr on rising edge
        word_t     reg_wdata;
        logic      resume;    // 1 for one cycle: continue at halt_pc + 1 (next instruction)
        logic      ebreak_halt; // 1: EBREAK halts (dcsr.ebreakm of the debug spec), 0: it traps
    } dbg_req_t;

    typedef struct packed {
        iaddr_t    halt_pc;   // address of the instruction that stopped the core
        word_t     reg_rdata; // value of register reg_addr, combinational
    } dbg_rsp_t;

    // Fetch -> next stage: the instruction that arrives from imem in this cycle
    // (EX in the 2-stage pipeline, ID in a 5-stage one).
    typedef struct packed {
        logic   valid;
        iaddr_t pc;
    } fetch_t;

    // Control -> Fetch.
    typedef struct packed {
        logic   run;      // 1: request the next instruction, 0: stop (fetch.valid drops)
        logic   stall;    // 1: keep pc, imem output and fetch: the instruction in EX stays
        logic   redirect; // 1: next request is at target; the request of this cycle is dropped
        iaddr_t target;
    } fetch_ctrl_t;

    // Branch -> Control: next pc of the instruction in EX, combinational.
    typedef struct packed {
        logic   taken;      // JAL, JALR, or a branch whose condition holds
        iaddr_t target;     // word address of the target
        logic   misaligned; // target byte address is not 4-byte aligned; with taken=1 a fault
    } branch_t;

    // Lsu -> Control.
    typedef struct packed {
        logic   stall;      // instruction in EX needs one more cycle (load waits for data)
        logic   misaligned; // load or store address not aligned to its size: a fault
    } lsu_t;

    // Control -> Csr: trap of the instruction in EX (machine mode).
    typedef struct packed {
        logic       valid;
        logic [4:0] cause;      // exception code for mcause, RiscvPkg CAUSE_*
        word_t      tval;       // value for mtval: address or instruction, 0 when none
    } trap_t;

    // Csr -> Control: where traps and MRET go.
    typedef struct packed {
        iaddr_t     mtvec;      // trap handler
        iaddr_t     mepc;       // MRET target
    } csr_t;

    // Lsu -> retire: memory access of the instruction in EX, RVFI fields, 0 when none.
    typedef struct packed {
        word_t  addr;       // word address as byte address
        strb_t  rmask;
        strb_t  wmask;
        word_t  rdata;      // valid in the second cycle of a load
        word_t  wdata;
    } lsu_mem_t;

    // Kind of instruction, from exact match with the RISC-V encodings.
    typedef enum logic [4:0] {
        KIND_ILLEGAL,   // any word that is not an RV32I instruction
        KIND_LUI,
        KIND_AUIPC,
        KIND_JAL,
        KIND_JALR,
        KIND_BRANCH,    // BEQ, BNE, BLT, BGE, BLTU, BGEU
        KIND_LOAD,      // LB, LH, LW, LBU, LHU
        KIND_STORE,     // SB, SH, SW
        KIND_OP_IMM,    // ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
        KIND_OP,        // ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
        KIND_FENCE,
        KIND_ECALL,
        KIND_EBREAK,
        KIND_CSR,       // CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
        KIND_MRET,
        KIND_WFI,
        KIND_MULDIV     // MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
    } kind_t;

    // Source of the value written to rd.
    typedef enum logic [2:0] {
        RD_ALU,         // Mig1Alu result: OP, OP-IMM, LUI, AUIPC
        RD_LINK,        // pc + 4: JAL, JALR
        RD_LOAD,        // loaded data
        RD_CSR,         // old value of the CSR: CSR instructions
        RD_MULDIV       // product or quotient/remainder: M instructions
    } rd_src_t;

    // Decode -> units: the instruction taken apart.
    typedef struct packed {
        kind_t      kind;
        reg_addr_t  rd;
        reg_addr_t  rs1;
        reg_addr_t  rs2;
        logic       rd_we;     // writes rd (writes to x0 are dropped by the register file)
        rd_src_t    rd_src;    // value written to rd
        logic       uses_rs1;  // reads rs1, for hazard detection in a 5-stage pipeline
        logic       uses_rs2;
        logic [2:0] funct3;    // operation within the kind: ALU op, branch compare, load/store size
        logic       alt;       // insn[30]: SUB instead of ADD, SRA/SRAI instead of SRL/SRLI
        word_t      imm;       // immediate of the instruction format, sign-extended
    } decoded_t;

endpackage
