/* Constants and types of Mig3: ports of Mig3Core, the signals between its parts, the
 * decode controls and the pipeline registers.
 *
 * Port groups of Mig3Core are packed structs, one struct per direction:
 * <group>_req_t goes from the requester, <group>_rsp_t comes back.
 * Modules import this package in their header, `module X import Mig3Pkg::*; #(`, and
 * their ports use its types (word_t, insn_t, iaddr_t, reg_id_t, ...).
 * Instruction and data addresses on ports are word addresses (iaddr_t, daddr_t),
 * register values are byte addresses like software sees them. The memory port's is a
 * byte address with a size, as AXI's: an uncached access goes out exactly.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package Mig3Pkg;

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

    // Configuration of Mig3 from cfg/mig3_config.yaml (Mig3ConfigPkg): modules that
    // read a knob take `parameter mig3_cfg_t CFG = MIG3_CFG`.
    typedef Mig3ConfigPkg::mig3_cfg_t mig3_cfg_t;
    localparam mig3_cfg_t MIG3_CFG = Mig3ConfigPkg::MIG3_CFG;

    // Cache lines: what both caches hold and the one memory moves (cfg cache_line_words).
    localparam LINE_WORDS = MIG3_CFG.cache_line_words;  // words in a line: 1 or 2
    localparam LINE_SIZE  = STRB_WIDTH * LINE_WORDS;     // bytes in a line
    localparam LINE_START = $clog2(LINE_SIZE);           // line addresses start at this bit

    typedef logic [WIDTH-1:0]           word_t;        // register value, data word
    typedef RiscvPkg::riscv_insn_t      insn_t;        // instruction (RiscvPkg)
    typedef logic [WIDTH-1:IADDR_START] iaddr_t;       // instruction address, word address
    typedef logic [WIDTH-1:DADDR_START] daddr_t;       // data address, word address
    typedef logic [STRB_WIDTH-1:0]      strb_t;        // byte enables of data word
    typedef logic [DADDR_START-1:0]     byte_offset_t; // byte in a data word
    typedef logic [REG_ID_WIDTH-1:0]    reg_id_t;      // register number x0..x31
    typedef logic [8*LINE_SIZE-1:0]     line_t;        // a cache line: what memory moves
    typedef logic [LINE_SIZE-1:0]       line_strb_t;   // byte enables of a line
    typedef logic [WIDTH-1:LINE_START]  laddr_t;       // line address
    typedef logic [2:0]                 size_t;        // bytes of an access: 1 << size
                                                       // (AXI AxSIZE)
    localparam size_t SIZE_B = 3'd0;                   // a byte
    localparam size_t SIZE_H = 3'd1;                   // a halfword
    localparam size_t SIZE_W = 3'd2;                   // a word

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
    localparam insn_t INSN_EBREAK = RiscvInstrPkg::EBREAK;

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
        BUBBLE_DIV,         // EX holds a division
        BUBBLE_IMEM,        // ID waits for the instruction from imem
        BUBBLE_DMEM         // a load or store waits for dmem: to take it, or a load's word
    } bubble_e;

    // Ports of Mig3Core

    // @kb: rtl/design/mig2/memory_channels
    // Memory channels: a request channel (valid/ready, AGENTS.md) and the answers to reads
    // (valid, no ready: every answer is taken), in order, one or more clocks after the
    // request was taken. A struct per direction: req_t from the requester, rsp_t to it (ready
    // of the request channel, the answer). imem_req_t: Mig3Fetch to the I-cache, a word
    // (the answer: the line that holds it, kb rtl/design/mig3/fetch_line);
    // dmem_req_t: Mig3Lsu to the D-cache, a word; mem_req_t: the one memory port of Mig3Core
    // behind both caches, a line, or an uncached access exactly (its byte address and size;
    // SimLatencyRAM in Mig3Cpu). Mig3Fetch waits for the
    // I-cache, EX and MEM/WB for the D-cache (Mig3Control).

    // Instruction fetch: the word at addr.
    typedef struct packed {
        logic   valid;
        iaddr_t addr;
    } imem_req_t;

    typedef struct packed {
        logic   ready;      // the request is taken when valid and ready
        logic   valid;      // data is the answer to a request
        line_t  data;       // the line of the word asked for
    } imem_rsp_t;

    // Data: we=1 writes the bytes of wdata with wstrb=1 and gets no answer, we=0 reads the
    // word at addr. offset and size are the access's own bytes (an uncached one goes out
    // exactly). An AMO is a read with an atop (AtomicPkg): wdata and wstrb are its
    // operand, the answer is the old word; it is done in front of the memory (Mig3Cpu,
    // kb rtl/lib/block/atomic/design).
    typedef struct packed {
        logic         valid;
        logic         we;
        daddr_t       addr;
        byte_offset_t offset;   // byte in the word: with addr, the byte address
        size_t        size;     // 1 << size bytes: a byte, a halfword or a word
        word_t        wdata;
        strb_t        wstrb;
        AtomicPkg::atop_t atop; // ATOP_NONE, or the AMO's operation
    } dmem_req_t;

    typedef struct packed {
        logic   ready;      // the request is taken when valid and ready
        logic   valid;      // data is the answer to a read
        word_t  data;
    } dmem_rsp_t;

    // Memory, behind the caches: the same for a line; a write writes the bytes of wdata
    // with wstrb=1 (a store's word, or an uncached store's); an AMO comes as asked, its
    // operand in every word of wdata.
    typedef struct packed {
        logic       valid;
        logic       we;
        word_t      addr;   // byte address: a line's (offset 0), or an uncached access's
        size_t      size;   // 1 << size bytes: the line, or the uncached access's
        line_t      wdata;
        line_strb_t wstrb;
        AtomicPkg::atop_t atop; // ATOP_NONE, or an AMO's operation
    } mem_req_t;

    typedef struct packed {
        logic   ready;      // the request is taken when valid and ready
        logic   valid;      // data is the answer to a read
        line_t  data;
    } mem_rsp_t;

    // Retire: one entry per retired instruction, RVFI (riscv-formal) fields and names.
    // Unlike other ports, addresses are byte addresses, as in RVFI. A register or
    // memory field that the instruction does not use is 0. Memory is RVFI "aligned
    // memory": mem_addr is word aligned, masks select the bytes of mem_rdata/mem_wdata.
    // RVFI fields that are constant for Mig3 are not here: intr=0, mode=3 (M), ixl=1.
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
        logic    stall;    // 1: keep pc, IF2 and ID, no request: the instruction in ID stays
        logic    redirect; // 1: next request is at target; the request of this cycle is dropped
        bubble_e why;      // redirect: reason of the bubble of the dropped request
        iaddr_t  target;
    } fetch_ctrl_t;

    // BTB (BranchTargetBuffer in Mig3Fetch): IF looks up the pc it requests; a hit predicted
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

    // Return-address stack (ReturnAddressStack in Mig3Core), used in ID.

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

    // Control -> Csr: trap of the instruction in EX (machine mode): an exception, or an
    // interrupt taken on it.
    typedef struct packed {
        logic                 valid;
        logic                 irq;      // an interrupt (mcause interrupt bit)
        RiscvPkg::excp_code_t cause;    // exception code for mcause, RiscvPkg CAUSE_*
        word_t                tval;     // value for mtval: address or instruction, 0 when none
    } trap_t;

    // Csr -> Control: where traps and MRET go, and whether an interrupt is to be taken.
    typedef struct packed {
        iaddr_t mtvec;      // trap handler
        iaddr_t mepc;       // MRET target
        logic   irq;        // an interrupt is pending and enabled: MEIP, MEIE and MIE
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
        KIND_ILLEGAL,   // any word that is not an instruction of Mig3
        KIND_LUI,
        KIND_AUIPC,
        KIND_JAL,
        KIND_JALR,
        KIND_BRANCH,    // BEQ, BNE, BLT, BGE, BLTU, BGEU
        KIND_LOAD,      // LB, LH, LW, LBU, LHU
        KIND_STORE,     // SB, SH, SW
        KIND_OP_IMM,    // ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI; RORI (Zbb)
        KIND_OP,        // ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND; Zbb in Mig3Alu
        KIND_FENCE,
        KIND_ECALL,
        KIND_EBREAK,
        KIND_CSR,       // CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
        KIND_MRET,
        KIND_WFI,
        KIND_MULDIV,    // MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
        KIND_BITMANIP,  // Zbb in ComputeCoreBitmanip: SEXT.B/H, ZEXT.H, ORC.B, REV8, CLZ, CTZ, CPOP
        KIND_LR,        // LR.W (Zalrsc): a load that reserves its word (Mig3Atomic)
        KIND_SC         // SC.W (Zalrsc): a store when the word is reserved, rd 0 or 1
    } kind_e;

    // Source of the value written to rd.
    typedef enum logic [2:0] {
        RD_ALU,         // Mig3Alu result: OP, OP-IMM, LUI, AUIPC
        RD_LINK,        // pc + 4: JAL, JALR
        RD_LOAD,        // loaded data
        RD_CSR,         // old value of the CSR: CSR instructions
        RD_MULDIV,      // product or quotient/remainder: M instructions
        RD_BITMANIP,    // ComputeCoreBitmanip result: Zbb with one operand
        RD_ATOMIC       // Mig3Atomic: SC's 0 (stored) or 1 (failed)
    } rd_src_e;

    // Decode -> parts: controls computed once in decode, one group per part; later
    // stages read them and do not decode again (AGENTS.md, Compute once, carry forward).
    typedef enum logic [1:0] {
        A_RS1,          // OP, OP-IMM, LOAD, STORE
        A_PC,           // AUIPC
        A_ZERO          // LUI
    } alu_a_e;

    typedef struct packed {
        alu_a_e         a;      // operand a
        logic           b_imm;  // operand b is imm, else rs2
        Alu2Pkg::ctrl_t alu2;   // the operation: Alu2Pkg::ctrl_of of its op (Mig3Decode)
    } alu_ctrl_t;

    typedef struct packed {
        logic   jump;       // JAL, JALR: always taken
        logic   branch;     // BRANCH: taken when the condition of funct3 holds
        logic   target_rs1; // target is rs1 + imm (JALR), else pc + imm
        logic   ret;        // JALR that is a return (see bubble_e): pops the return stack
        logic   call;       // JAL, JALR whose rd is a link register: pushes the return stack
    } br_ctrl_t;

    typedef struct packed {
        logic   read;       // LOAD, LR.W
        logic   write;      // STORE, SC.W
    } mem_ctrl_t;

    typedef struct packed {
        logic   lr;         // LR.W: reserves its word
        logic   sc;         // SC.W: stores only when its word is reserved
    } atomic_ctrl_t;

    typedef struct packed {
        logic   csr;        // CSR instruction (Mig3Csr)
        logic   mret;
        logic   ecall;
        logic   ebreak;
        logic   illegal;    // no instruction of Mig3: illegal instruction trap
    } sys_ctrl_t;

    typedef struct packed {
        logic   en;         // M instruction (Mig3MulDiv)
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
        logic              uses_rs1; // reads rs1, for the interlock (Mig3Control)
        logic              uses_rs2;
        alu_ctrl_t         alu;      // Mig3Alu
        br_ctrl_t          br;       // Mig3Branch
        mem_ctrl_t         mem;      // Mig3Lsu
        atomic_ctrl_t      atomic;   // Mig3Atomic
        sys_ctrl_t         sys;      // Mig3Control, Mig3Csr
        muldiv_ctrl_t      muldiv;   // Mig3MulDiv
        ComputeCoreBitmanipPkg::bm_op_e bitmanip;   // ComputeCoreBitmanip: the operation
        RiscvPkg::funct3_t funct3;   // operation within a part: ALU op, branch compare,
                                     // load/store size
        logic              alt;      // insn[30]: SUB instead of ADD, SRA/SRAI instead of SRL/SRLI
        word_t             imm;      // immediate of the instruction format, sign-extended
    } decoded_t;

    // Pipeline registers

    // ID -> EX: the instruction taken apart with its register values (Mig3Pipe).
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

    // EX -> MEM/WB: the instruction after EX (Mig3Pipe). No stall or flush: an
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
        logic    ex_stall;   // EX keeps its instruction (division, waiting for dmem)
        logic    ex_flush;   // EX gets a bubble: ID can not go on, or it is dropped
        bubble_e ex_why;     // ex_flush: reason of the bubble
        logic    mem_stall;  // MEM/WB keeps its load: its word has not come from dmem
    } pipe_ctrl_t;

    // Mig3Core -> testbench: the pipeline view (Konata): the slot of every stage in this
    // cycle and how the slots move at the rising edge. The core only reports it.
    typedef struct packed {
        logic   if_req;     // the instruction at if_pc enters IF2 (asked of imem, or kept)
        iaddr_t if_pc;
        fetch_t if2;        // slots: valid, bubble reason, pc; IF2 also while it waits
        fetch_t id;
        fetch_t ex;
        fetch_t mem;        // MEM/WB
        logic   redirect;   // what would enter IF2 and ID is dropped (redirect, halt)
        logic   if2_wait;   // the instruction in IF2 waits for its word from imem
        logic   if2_stall;  // IF2 keeps its slot (ID stalls, or it waits for imem)
        logic   id_stall;   // ID keeps its instruction (load-use, division)
        logic   ex_stall;   // EX keeps its instruction (division, waiting for dmem)
        logic   ex_flush;   // EX gets a bubble; without id_stall the instruction in ID dies
        logic   mem_wait;   // MEM/WB keeps its load: it waits for its word from dmem
    } pipe_trace_t;

endpackage
