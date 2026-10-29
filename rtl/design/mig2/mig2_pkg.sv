/* Constants and types of Mig2: ports of Mig2Core, the signals between its parts, the
 * decode controls and the pipeline registers.
 *
 * Port groups of Mig2Core are packed structs, one struct per direction:
 * <group>_req_t goes from the requester, <group>_rsp_t comes back.
 * Modules import this package in their header, `module X import Mig2Pkg::*; #(`, and
 * their ports use its types (word_t, insn_t, iaddr_t, reg_id_t, ...).
 * Instruction and data addresses on ports are word addresses (iaddr_t, daddr_t),
 * register values are byte addresses like software sees them.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package Mig2Pkg;

    // ISA facts.
    localparam WIDTH          = 32;                 // register and data width (RISC-V XLEN)
    localparam STRB_WIDTH     = WIDTH / 8;          // bytes in data word
    localparam REG_ID_WIDTH   = 5;                  // 32 registers x0..x31
    localparam IADDR_START    = 2;                  // instructions are 4-byte aligned
                                                    // (2-byte with the C extension)
    localparam DADDR_START    = $clog2(STRB_WIDTH); // data words are STRB_WIDTH-byte aligned

    // Constants below are for all modules and testbenches; a design with one
    // module as top, like a unit test, uses only some of them.
    /* verilator lint_off UNUSEDPARAM */

    // Configuration of Mig2 from cfg/mig2_config.yaml (Mig2ConfigPkg): modules that
    // read a knob take `parameter mig2_cfg_t CFG = MIG2_CFG`.
    typedef Mig2ConfigPkg::mig2_cfg_t mig2_cfg_t;
    localparam mig2_cfg_t MIG2_CFG = Mig2ConfigPkg::MIG2_CFG;

    typedef logic [WIDTH-1:0]           word_t;        // register value, data word
    typedef RiscvPkg::riscv_insn_t      insn_t;        // instruction (RiscvPkg)
    typedef logic [WIDTH-1:IADDR_START] iaddr_t;       // instruction address, word address
    typedef logic [WIDTH-1:DADDR_START] daddr_t;       // data address, word address
    typedef logic [STRB_WIDTH-1:0]      strb_t;        // byte enables of data word
    typedef logic [DADDR_START-1:0]     byte_offset_t; // byte in a data word
    typedef logic [REG_ID_WIDTH-1:0]    reg_id_t;      // register number x0..x31

    // Two words, hi and lo: a 64-bit value on RV32 (a product, a 64-bit counter).
    typedef struct packed {
        word_t hi;      // upper word
        word_t lo;      // lower word
    } dword_t;

    // A jump or branch target is not a legal instruction address: bit 1 is set (bit 0 is 0
    // for JAL and branches, JALR ignores it). With the C extension it never is.
    // Only bit 1 of the target is used.
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic target_misaligned(word_t target);
        return target[1];
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // Instructions with fixed encoding.
    localparam insn_t INSN_EBREAK = 32'h0010_0073;

    /* verilator lint_on UNUSEDPARAM */

    // Bubble: a pipeline slot without an instruction (valid=0), and why it is empty. The
    // pipeline registers carry it, retire reports it: every cycle retires an instruction
    // or a bubble, so the reasons add up to all cycles that retire nothing. Redirect
    // classes are those of branch prediction; a return is a JALR whose rs1 is a link
    // register (x1, x5), unless rd = rs1 (hint table of JAL/JALR, RISC-V unprivileged spec).
    typedef enum logic [3:0] {
        BUBBLE_NONE,        // not a bubble: an instruction
        BUBBLE_FILL,        // the pipeline fills: after reset, after a halt (resume)
        BUBBLE_COND_BRANCH, // conditional branch guessed wrong: EX corrects the guess
        BUBBLE_PRED_TAKEN,  // conditional branch guessed taken: ID redirects
        BUBBLE_BTB_FIX,     // the BTB sent fetch where the instruction does not go: ID
                            // corrects it (two pcs share an entry; not with a full tag)
        BUBBLE_DIR_JUMP,    // JAL: target pc + imm (calls too)
        BUBBLE_INDIR_JUMP,  // JALR that is not a return (indirect calls too)
        BUBBLE_RET,         // JALR that is a return: not predicted, or predicted wrong (EX)
        BUBBLE_PRED_RET,    // return predicted by the return-address stack: ID redirects
        BUBBLE_TRAP,        // fault, ECALL, EBREAK as a breakpoint: fetch goes to mtvec
        BUBBLE_XRET,        // MRET: fetch goes to mepc
        BUBBLE_LOAD_USE,    // the next instruction waits for load data
        BUBBLE_DIV          // EX holds a division
    } bubble_e;

    // Ports of Mig2Core

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
    // RVFI fields that are constant for Mig2 are not here: intr=0, mode=3 (M), ixl=1.
    // bubble is not RVFI: with valid=0 it tells why nothing retires in this cycle.
    typedef struct packed {
        logic        valid;      // an instruction retires: it completes, or traps
        bubble_e     bubble;     // valid=0: reason of the bubble that retires instead
        logic [63:0] order;      // index of the retired instruction: 0, 1, 2, ...
        insn_t       insn;
        logic        trap;       // the instruction faulted: no register or memory write
        word_t       pc_rdata;   // address of the instruction
        word_t       pc_wdata;   // address of the next instruction
        reg_id_t     rs1_addr;   // registers read, 0 when not read (RVFI names)
        word_t       rs1_rdata;
        reg_id_t     rs2_addr;
        word_t       rs2_rdata;
        reg_id_t     rd_addr;    // register written, 0 when none (also for x0)
        word_t       rd_wdata;
        word_t       mem_addr;   // load or store: word address as byte address
        strb_t       mem_rmask;  // bytes read
        strb_t       mem_wmask;  // bytes written
        word_t       mem_rdata;  // word read
        word_t       mem_wdata;  // word written, bytes of mem_wmask
    } retire_t;

    // Debug, used while the core is halted.
    typedef struct packed {
        reg_id_t reg_id;        // register to read or write
        logic    reg_wr;        // 1: write reg_wdata into register reg_id on rising edge
        word_t   reg_wdata;
        logic    resume;        // 1 for one cycle: continue at halt_pc + 1 (next instruction)
        logic    ebreak_halt;   // 1: EBREAK halts (dcsr.ebreakm of the debug spec), 0: traps
    } dbg_req_t;

    typedef struct packed {
        iaddr_t  halt_pc;       // address of the instruction that stopped the core
        word_t   reg_rdata;     // value of register reg_id, combinational
    } dbg_rsp_t;

    // Between the parts

    // IF -> ID: the instruction that arrives from imem in this cycle.
    typedef struct packed {
        logic    valid;
        bubble_e bubble;    // valid=0: why there is no instruction
        iaddr_t  pc;
    } fetch_t;

    // Control -> Fetch.
    typedef struct packed {
        logic    run;      // 1: request the next instruction, 0: stop (fetch.valid drops)
        logic    stall;    // 1: keep pc, imem output and fetch: the instruction in EX stays
        logic    redirect; // 1: next request is at target; the request of this cycle is dropped
        bubble_e why;      // redirect: reason of the bubble of the dropped request
        iaddr_t  target;
    } fetch_ctrl_t;

    // BTB (BranchTargetBuffer in Mig2Fetch): IF looks up the pc it requests; a hit predicted
    // taken sends fetch to the target in the same cycle, without a bubble.

    // Fetch -> ID -> EX: what the BTB said for the instruction in IF; it goes with the
    // instruction, so that EX updates the entry without reading it again.
    typedef struct packed {
        logic                       hit;
        logic                       taken;      // hit with a counter that says taken: IF
                                                // went to the target
        BranchCounterPkg::counter_e counter;
    } btb_pred_t;

    // Control -> Fetch: a conditional branch or a JAL completed in EX: the BTB learns it.
    typedef struct packed {
        logic                       en;
        iaddr_t                     pc;
        logic                       hit;        // hit and counter of its lookup (btb_pred_t)
        BranchCounterPkg::counter_e counter;
        logic                       taken;
        iaddr_t                     target;     // also when not taken
    } btb_update_t;

    // Control -> Fetch: the BTB sent fetch where the instruction in ID does not go: its
    // entry is cleared.
    typedef struct packed {
        logic   en;
        iaddr_t pc;
    } btb_inval_t;

    // Return-address stack (ReturnAddressStack in Mig2Core), used in ID.

    // Control -> stack: a call that leaves ID pushes its return address, a return pops; both
    // for a swap (a coroutine: the top is replaced).
    typedef struct packed {
        logic   push;
        logic   pop;
        iaddr_t push_addr;  // the address after the call
    } ras_ctrl_t;

    // Branch -> Control: next pc of the instruction in EX, combinational.
    typedef struct packed {
        logic   taken;      // JAL, JALR, or a branch whose condition holds
        iaddr_t target;     // word address of the target
        logic   misaligned; // target byte address is not 4-byte aligned; with taken=1 a fault
    } branch_t;

    // Control -> Csr: trap of the instruction in EX (machine mode).
    typedef struct packed {
        logic                 valid;
        RiscvPkg::excp_code_t cause;    // exception code for mcause, RiscvPkg CAUSE_*
        word_t                tval;     // value for mtval: address or instruction, 0 when none
    } trap_t;

    // Csr -> Control: where traps and MRET go.
    typedef struct packed {
        iaddr_t mtvec;      // trap handler
        iaddr_t mepc;       // MRET target
    } csr_t;

    // Lsu -> retire: memory access of the instruction in EX, RVFI fields, 0 when none;
    // mem_rdata of loads is filled in MEM/WB, where the data arrives.
    typedef struct packed {
        word_t  addr;       // word address as byte address
        strb_t  rmask;
        strb_t  wmask;
        word_t  wdata;
    } lsu_mem_t;

    // Decode

    // Kind of instruction, from exact match with the RISC-V encodings.
    typedef enum logic [4:0] {
        KIND_ILLEGAL,   // any word that is not an instruction of Mig2
        KIND_LUI,
        KIND_AUIPC,
        KIND_JAL,
        KIND_JALR,
        KIND_BRANCH,    // BEQ, BNE, BLT, BGE, BLTU, BGEU
        KIND_LOAD,      // LB, LH, LW, LBU, LHU
        KIND_STORE,     // SB, SH, SW
        KIND_OP_IMM,    // ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI; RORI (Zbb)
        KIND_OP,        // ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND; Zbb in Mig2Alu
        KIND_FENCE,
        KIND_ECALL,
        KIND_EBREAK,
        KIND_CSR,       // CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
        KIND_MRET,
        KIND_WFI,
        KIND_MULDIV,    // MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
        KIND_BITMANIP   // SEXT.B, SEXT.H, ZEXT.H, ORC.B, REV8: Zbb in ComputeCoreBitmanip
    } kind_e;

    // Source of the value written to rd.
    typedef enum logic [2:0] {
        RD_ALU,         // Mig2Alu result: OP, OP-IMM, LUI, AUIPC
        RD_LINK,        // pc + 4: JAL, JALR
        RD_LOAD,        // loaded data
        RD_CSR,         // old value of the CSR: CSR instructions
        RD_MULDIV,      // product or quotient/remainder: M instructions
        RD_BITMANIP     // ComputeCoreBitmanip result: Zbb with one operand
    } rd_src_e;

    // Decode -> parts: controls computed once in decode, one group per part; later
    // stages read them and do not decode again (AGENTS.md, Compute once, carry forward).
    typedef enum logic [1:0] {
        A_RS1,          // OP, OP-IMM, LOAD, STORE
        A_PC,           // AUIPC
        A_ZERO          // LUI
    } alu_a_e;

    typedef struct packed {
        alu_a_e a;          // operand a
        logic   b_imm;      // operand b is imm, else rs2
        logic   op;         // funct3 selects the operation (OP, OP-IMM), else a + b
        logic   sub;        // OP with alt: SUB instead of ADD
        logic   b_inv;      // Zbb ANDN, ORN, XNOR: AND, OR, XOR with b inverted
        logic   minmax;     // Zbb MIN, MINU, MAX, MAXU: the compare of SLT/SLTU selects a or b
        logic   minmax_max;         // MAX, MAXU: the larger
        logic   minmax_unsigned;    // MINU, MAXU: unsigned compare
        logic   rotate;     // Zbb ROL, ROR, RORI: the shifter rotates (funct3 of SLL, SRL)
    } alu_ctrl_t;

    typedef struct packed {
        logic   jump;       // JAL, JALR: always taken
        logic   branch;     // BRANCH: taken when the condition of funct3 holds
        logic   target_rs1; // target is rs1 + imm (JALR), else pc + imm
        logic   ret;        // JALR that is a return (see bubble_e): pops the return stack
        logic   call;       // JAL, JALR whose rd is a link register: pushes the return stack
    } br_ctrl_t;

    typedef struct packed {
        logic   read;       // LOAD
        logic   write;      // STORE
    } mem_ctrl_t;

    typedef struct packed {
        logic   csr;        // CSR instruction (Mig2Csr)
        logic   mret;
        logic   ecall;
        logic   ebreak;
        logic   illegal;    // no instruction of Mig2: illegal instruction trap
    } sys_ctrl_t;

    typedef struct packed {
        logic   en;         // M instruction (Mig2MulDiv)
        logic   div;        // DIV, DIVU, REM, REMU: the divider, else the multiplier
        logic   rem;        // REM, REMU: the remainder, else the quotient
        logic   mul_lo;     // MUL: the lower half of the product, else the upper half
        logic   a_signed;   // MULH, MULHSU: rs1 is signed
        logic   b_signed;   // MULH: rs2 is signed
        logic   div_signed; // DIV, REM
    } muldiv_ctrl_t;

    // Decode -> parts: the instruction taken apart, with the controls of every part.
    typedef struct packed {
        kind_e             kind;     // for testbenches and traces; parts read the controls
        reg_id_t           rd;
        reg_id_t           rs1;
        reg_id_t           rs2;
        logic              rd_we;    // writes rd (writes to x0 are dropped by the register file)
        rd_src_e           rd_src;   // value written to rd
        logic              uses_rs1; // reads rs1, for the interlock (Mig2Control)
        logic              uses_rs2;
        alu_ctrl_t         alu;      // Mig2Alu
        br_ctrl_t          br;       // Mig2Branch
        mem_ctrl_t         mem;      // Mig2Lsu
        sys_ctrl_t         sys;      // Mig2Control, Mig2Csr
        muldiv_ctrl_t      muldiv;   // Mig2MulDiv
        ComputeCoreBitmanipPkg::bm_op_e bitmanip;   // ComputeCoreBitmanip: the operation
        RiscvPkg::funct3_t funct3;   // operation within a part: ALU op, branch compare,
                                     // load/store size
        logic              alt;      // insn[30]: SUB instead of ADD, SRA/SRAI instead of SRL/SRLI
        word_t             imm;      // immediate of the instruction format, sign-extended
    } decoded_t;

    // Pipeline registers

    // ID -> EX: the instruction taken apart with its register values (Mig2Pipe).
    typedef struct packed {
        logic      valid;
        bubble_e   bubble;      // valid=0: why there is no instruction
        iaddr_t    pc;
        insn_t     insn;
        decoded_t  dec;
        logic      redirected;  // fetch went to the target: the BTB in IF, or ID (JAL,
                                // branch guessed taken)
        btb_pred_t btb;         // what the BTB said in IF: hit and counter, for its update
        iaddr_t    ras_target;  // where ID sent a return: the top of the return stack
        word_t     rs1_data;    // read in ID; no older instruction writes rs1 (interlock)
        word_t     rs2_data;
    } id_ex_t;

    // EX -> MEM/WB: the instruction after EX (Mig2Pipe). No stall or flush: an
    // instruction that leaves EX always completes in MEM/WB.
    typedef struct packed {
        logic              valid;   // completes or traps
        bubble_e           bubble;  // valid=0: why nothing completes in EX
        retire_t           ret;     // RVFI entry built in EX; MEM/WB fills valid, bubble,
                                    // order, and rd_wdata and mem_rdata of loads
        logic              load;    // rd value comes from dmem
        RiscvPkg::funct3_t funct3;  // load size and sign
        byte_offset_t      offset;  // load: byte in the word
    } ex_mem_t;

    // Control -> Pipe, per boundary: keep the instruction (stall) or put a bubble (flush).
    typedef struct packed {
        logic    ex_stall;   // EX keeps its instruction (division)
        logic    ex_flush;   // EX gets a bubble: ID can not go on, or it is dropped
        bubble_e ex_why;     // ex_flush: reason of the bubble
    } pipe_ctrl_t;

    // Mig2Core -> testbench: the pipeline view (Konata): the slot of every stage in this
    // cycle and how the slots move at the rising edge. The core only reports it.
    typedef struct packed {
        logic   if_req;     // IF requests the instruction at if_pc from imem
        iaddr_t if_pc;
        fetch_t id;         // slots: valid, bubble reason, pc
        fetch_t ex;
        fetch_t mem;        // MEM/WB
        logic   redirect;   // the request of this cycle is dropped
        logic   id_stall;   // IF and ID keep their instruction (load-use, division)
        logic   ex_stall;   // EX keeps its instruction (division)
        logic   ex_flush;   // EX gets a bubble; without id_stall the instruction in ID dies
    } pipe_trace_t;

endpackage
