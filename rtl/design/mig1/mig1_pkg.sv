/* Constants and port types of Mig1 RISC-V CPU.
 *
 * Port groups of Mig1Core are packed structs, one struct per direction:
 * <group>_req_t goes from the requester, <group>_rsp_t comes back.
 * Modules import this package in their header, `module X import Mig1Pkg::*; #(`:
 * Icarus 11 crashes (assert in elab_type.cc) when the structs are used only as
 * Mig1Pkg::<type> and no module imports the package.
 * Instruction and data addresses on ports are word addresses (iaddr_t, daddr_t),
 * register values are byte addresses like software sees them.
 */
package Mig1Pkg;

    localparam WIDTH            = 32;                 // register and data width (RISC-V XLEN)
    localparam INSN_WIDTH       = 32;                 // instruction width, 32 also for RV64
    localparam STRB_WIDTH       = WIDTH / 8;          // bytes in data word
    localparam REG_ADDR_WIDTH   = 5;                  // 32 registers x0..x31
    localparam IADDR_START      = 2;                  // instructions are 4-byte aligned (1 with C extension)
    localparam DADDR_START      = $clog2(STRB_WIDTH); // data words are STRB_WIDTH-byte aligned
    localparam DEFAULT_RST_ADDR = 32'h0000_0000;      // default PC after reset, byte address
    // Used by Mig1Cpu, not by Mig1Core alone.
    /* verilator lint_off UNUSEDPARAM */
    localparam MEM_ADDR_WIDTH   = 16;                 // Mig1Cpu: 64 KiB ROM and 64 KiB RAM
    /* verilator lint_on UNUSEDPARAM */

    typedef logic [WIDTH-1:0]           word_t;      // register value, data word
    typedef logic [INSN_WIDTH-1:0]      insn_t;      // instruction
    typedef logic [WIDTH-1:IADDR_START] iaddr_t;     // instruction address, word address
    typedef logic [WIDTH-1:DADDR_START] daddr_t;     // data address, word address
    typedef logic [STRB_WIDTH-1:0]      strb_t;      // byte enables of data word
    typedef logic [REG_ADDR_WIDTH-1:0]  reg_addr_t;  // register number

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

    // Retire: valid=1 for one cycle when an instruction has finished.
    typedef struct packed {
        logic      valid;
        iaddr_t    pc;        // address of the instruction
        insn_t     insn;      // the instruction
        reg_addr_t rd;        // register written, 0 when none
        word_t     rd_data;   // value written to rd
    } retire_t;

    // Debug, used while the core is halted.
    typedef struct packed {
        reg_addr_t reg_addr;  // register to read or write
        logic      reg_wr;    // 1: write reg_wdata into reg_addr on rising edge
        word_t     reg_wdata;
        logic      resume;    // 1 for one cycle: continue at halt_pc + 1 (next instruction)
    } dbg_req_t;

    typedef struct packed {
        iaddr_t    halt_pc;   // address of the instruction that stopped the core
        word_t     reg_rdata; // value of register reg_addr, combinational
    } dbg_rsp_t;

endpackage
