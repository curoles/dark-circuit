/* Retire checks of Mig3: every retired instruction against the program, the memories and a
 * shadow copy of the registers; the retire lines of the trace.
 *
 * retire is the RVFI trace of the core (see Mig3Pkg). Checks of every retired instruction:
 * - retire.insn is the imem word at pc_rdata: fetch gets the right instruction,
 * - the first retired pc is the reset address, order counts 0, 1, 2, ...,
 * - pc_rdata is pc_wdata of the previous retired instruction (control flow),
 * - rs1_rdata, rs2_rdata are the shadow registers (registers read), 0 for x0,
 * - load or store: mem_addr and the mask are the access of the instruction:
 *   address rs1_rdata + imm, size by funct3 (computed here from insn),
 * - load: bytes of mem_rdata under mem_rmask are the bytes of the memory with the retired
 *   stores the memory has not taken yet on top (a store may wait in the arbiter's buffer
 *   and one in the D-cache while a later load hits the line they wrote),
 * - LR.W is a load of rs1, SC.W a store of rs1 when it succeeds: a shadow reservation
 *   (an LR takes it; an SC, a trap and MRET end it) says whether it does; rd must be 0
 *   then, else 1 and no access,
 * - store: it is the next write the memory takes, in program order: mem_addr, mem_wmask and
 *   the bytes of mem_wdata under it (the D-cache writes through: the memory takes the store
 *   in the cycle it retires or later, uncached in EX, before it retires; a store still on
 *   its way when the run ends is not checked),
 * - traps only with allow_trap,
 * - nothing retires while halted,
 * - no X or Z in retire (Icarus only, Verilator is 2-state),
 * - with +expect_sequential: every pc is the previous pc + 4 (straight-line code).
 * Register writes of retire (rd_addr, rd_wdata) and of the debugger (dbg_req while halt)
 * are kept in a shadow copy of the registers. The trace gets a line per retired
 * instruction, debugger register write and resume. Memory is read with peek() of the
 * memory of Mig3Cpu, all in mem_byte(), and the writes the memory takes are seen in
 * dmem_write(): the two places that name it. Stops at the first failure with $fatal.
 *
 * TbMig3 instantiates it; it reads its ports, TbMig3 reads its outputs.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig3RetireCheck import Mig3Pkg::*, RiscvPkg::*; (
    input  wire         clk,
    input  wire         rst_n,              // synchronous reset, active low
    input  wire         halt,               // core halted: the debugger may write registers
    input  wire         halted,             // TbMig3 handles a halt: nothing may retire
    input  wire         allow_trap,         // a retired trap is no failure
    // All fields but bubble are used (bubbles: TbMig3BubbleCheck).
    /* verilator lint_off UNUSEDSIGNAL */
    input  retire_t     retire,
    /* verilator lint_on UNUSEDSIGNAL */
    // Only reg_id, reg_wr, reg_wdata and resume are used: writes of the debugger.
    /* verilator lint_off UNUSEDSIGNAL */
    input  dbg_req_t    dbg_req,
    /* verilator lint_on UNUSEDSIGNAL */
    input  integer      cycle,              // cycle number of the trace (TbMig3)
    input  integer      trace_fd,           // trace file of TbMig3, 0: no trace
    output integer      retired,            // instructions retired so far
    output integer      traps,              // retired instructions that trapped
    output logic        ebreak_trapped,     // an EBREAK has trapped
    output word_t       shadow [32],        // registers written by retire and the debugger
    output logic [31:0] written             // bit r: shadow[r] was written
);
    import RiscvInstrPkg::*;

    localparam AW = MIG3_CFG.mem_addr_width;

    logic  expect_sequential;               // +expect_sequential
    word_t retire_pc;                       // byte address
    word_t prev_pc;
    word_t prev_pc_wdata;                   // next pc told by the previous retired instruction
    word_t access_addr;                     // load or store in retire: byte address
    strb_t access_mask;                     // its bytes
    logic  resv_valid;                      // shadow reservation of LR/SC: a word is
    daddr_t resv_addr;                      // reserved, its word address

    // A store: retired, or a write dmem takes. Matched in program order.
    typedef struct packed {
        word_t pc;                          // byte address, 0 for a write of dmem
        word_t addr;                        // word aligned byte address
        strb_t mask;
        word_t data;
    } store_t;

    store_t retired_stores [$];             // retired, not taken by dmem yet
    store_t dmem_writes [$];                // taken by dmem, not retired yet (uncached)
    store_t dmem_taken;                     // the write dmem takes at this edge

    assign retire_pc = retire.pc_rdata;

    // The only access to the memory of Mig3Cpu (code and data): byte at address a; imem
    // only says which of the two the caller means.
    // Memories wrap around: only the AW low bits of an address are used.
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [7:0] mem_byte(input logic imem, input word_t a);
        return TbMig3.u_mig3_cpu.u_mem.peek(a[AW-1:0]);
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // Word at byte address a of imem or dmem, little-endian.
    function automatic word_t mem_word(input logic imem, input word_t a);
        word_t ab;
        for (int b = 0; b < 4; b++) begin
            ab = a + b;
            mem_word[8*b +: 8] = mem_byte(imem, ab);
        end
    endfunction

    // Access that the load or store in retire must make

    typedef enum logic [1:0] {
        MEM_NONE,
        MEM_LOAD,
        MEM_STORE,
        MEM_SC      // a store when it succeeds
    } mem_kind_e;

    // Kind of memory access of insn.
    function automatic mem_kind_e mem_kind(input insn_t insn);
        casez (insn)
            LB, LH, LW, LBU, LHU: return MEM_LOAD;
            LR_W:                 return MEM_LOAD;
            SB, SH, SW:           return MEM_STORE;
            SC_W:                 return MEM_SC;
            default:              return MEM_NONE;
        endcase
    endfunction

    // Byte address of the load or store insn when rs1 is base: base + S or I immediate;
    // LR and SC have none.
    function automatic word_t mem_byte_addr(input insn_t insn, input word_t base);
        if (insn ==? LR_W || insn ==? SC_W)
            return base;
        return base + (mem_kind(insn) == MEM_STORE ? imm_s_of(insn) : imm_i_of(insn));
    endfunction

    // Bytes of the access of insn at byte offset `offset` in the word: size by funct3.
    function automatic strb_t mem_mask(input insn_t insn, input byte_offset_t offset);
        insn_fmt_t f;
        strb_t     size;
        f.word = insn;
        case (f.i.funct3)
            F3_B, F3_BU: size = 4'b0001;
            F3_H, F3_HU: size = 4'b0011;
            default:     size = 4'b1111;
        endcase
        return size << offset;
    endfunction

    assign access_addr = mem_byte_addr(retire.insn, retire.rs1_rdata);
    assign access_mask = mem_mask(retire.insn, access_addr[DADDR_START-1:0]);

    // Bytes of data under mask are the bytes of the memory in the word at a, with the
    // retired stores it has not taken yet on top, oldest first.
    function automatic logic dmem_has(input word_t a, input strb_t mask, input word_t data);
        word_t      ab;
        logic [7:0] m;
        for (int b = 0; b < STRB_WIDTH; b++) begin
            ab = a + b;
            m  = mem_byte(1'b0, ab);
            foreach (retired_stores[i])
                if (retired_stores[i].addr[WIDTH-1:DADDR_START] == ab[WIDTH-1:DADDR_START] &&
                    retired_stores[i].mask[ab[DADDR_START-1:0]])
                    m = retired_stores[i].data[8*ab[DADDR_START-1:0] +: 8];
            if (mask[b] && m !== data[8*b +: 8])
                return 1'b0;
        end
        return 1'b1;
    endfunction

    // The write the memory of Mig3Cpu takes at this edge: 1 and the write in w, or 0. The
    // memory moves lines; a store writes one word of it, the one its strobes are in.
    function automatic logic dmem_write(output store_t w);
        line_t      data;
        line_strb_t strb;
        int         k;      // the word of the line
        data = TbMig3.u_mig3_cpu.mem_req.wdata;
        strb = TbMig3.u_mig3_cpu.mem_req.wstrb;
        k    = 0;
        for (int i = 0; i < LINE_WORDS; i++)
            if (strb[STRB_WIDTH*i +: STRB_WIDTH] != '0)
                k = i;
        w.pc   = '0;
        w.addr = {TbMig3.u_mig3_cpu.mem_req.addr[WIDTH-1:LINE_START], {LINE_START{1'b0}}} +
                 word_t'(STRB_WIDTH * k);
        w.mask = strb[STRB_WIDTH*k +: STRB_WIDTH];
        w.data = data[WIDTH*k +: WIDTH];
        return TbMig3.u_mig3_cpu.mem_req.valid && TbMig3.u_mig3_cpu.mem_req.we &&
               TbMig3.u_mig3_cpu.mem_rsp.ready;
    endfunction

    // Each retired store is the next write dmem takes: pairs them in order.
    task automatic match_stores;
        store_t s;
        // A write of dmem: its pc (0) is not used.
        /* verilator lint_off UNUSEDSIGNAL */
        store_t w;
        /* verilator lint_on UNUSEDSIGNAL */
        word_t  bits;     // the bits of the store's bytes
        while (retired_stores.size() > 0 && dmem_writes.size() > 0) begin
            s = retired_stores.pop_front();
            w = dmem_writes.pop_front();
            for (int b = 0; b < STRB_WIDTH; b++)
                bits[8*b +: 8] = {8{s.mask[b]}};
            if (w.addr !== s.addr || w.mask !== s.mask || ((w.data ^ s.data) & bits) !== '0)
                $fatal(1, "Mig3: store at %h to %h mask %b data %h, dmem took %h mask %b data %h",
                       s.pc, s.addr, s.mask, s.data, w.addr, w.mask, w.data);
        end
        // A retired store may wait in the arbiter's buffer and one more in the D-cache (held:
        // it takes no request then); uncached, the memory takes a store one cycle before it
        // retires. So two on the retired side, one on the other, not more (no store is lost).
        if (retired_stores.size() > 2 || dmem_writes.size() > 1)
            $fatal(1, "Mig3: %0d retired stores not taken by dmem, %0d writes of dmem not retired",
                   retired_stores.size(), dmem_writes.size());
    endtask

    // Checks of every retired instruction

    // Register r read by the instruction in retire gave data: the shadow value, 0 for x0
    // and for an unused register (r = 0).
    task automatic check_read(input reg_id_t r, input word_t data);
        if (r == 0 && data !== '0)
            $fatal(1, "Mig3: pc %h read data of x0 or of an unused register is not 0", retire_pc);
        if (r != 0 && written[r] && data !== shadow[r])
            $fatal(1, "Mig3: pc %h read x%0d = %h, expected %h", retire_pc, r, data, shadow[r]);
    endtask

    // Load or store in retire that did not trap: its address and mask are access_addr
    // and access_mask, the mask of the other direction is 0.
    task automatic check_access;
        logic  load;
        word_t word_addr;     // access_addr, word aligned
        strb_t mask;          // mem_rmask of a load, mem_wmask of a store
        strb_t other_mask;    // the other one
        load       = mem_kind(retire.insn) == MEM_LOAD;
        word_addr  = {access_addr[WIDTH-1:DADDR_START], {DADDR_START{1'b0}}};
        mask       = load ? retire.mem_rmask : retire.mem_wmask;
        other_mask = load ? retire.mem_wmask : retire.mem_rmask;
        if (retire.mem_addr !== word_addr || mask !== access_mask || other_mask !== '0)
            $fatal(1, "Mig3: pc %h accesses mem[%h] r %b w %b, expected address %h mask %b",
                   retire_pc, retire.mem_addr, retire.mem_rmask, retire.mem_wmask,
                   access_addr, access_mask);
    endtask

    // SC in retire that did not trap: it succeeds when the shadow reservation holds its
    // word; then rd gets 0 and it is a store of its word, else rd gets 1 and it accesses
    // nothing.
    task automatic check_sc;
        logic ok;
        ok = resv_valid && resv_addr == access_addr[WIDTH-1:DADDR_START];
        if (retire.rd_addr != 0 && retire.rd_wdata !== word_t'(!ok))
            $fatal(1, "Mig3: SC at pc %h wrote %h, expected %0d (reserved %0d, word %h)",
                   retire_pc, retire.rd_wdata, !ok, resv_valid, {resv_addr, {DADDR_START{1'b0}}});
        if (ok)
            check_access();
        else if (retire.mem_rmask != 0 || retire.mem_wmask != 0)
            $fatal(1, "Mig3: SC at pc %h failed, but accesses mem[%h] r %b w %b",
                   retire_pc, retire.mem_addr, retire.mem_rmask, retire.mem_wmask);
    endtask

    // The shadow reservation, in program order: an LR takes it; an SC, a trap and MRET
    // end it.
    always @(posedge clk)
        if (!rst_n)
            resv_valid <= 1'b0;
        else if (retire.valid) begin
            if (retire.trap || retire.insn ==? SC_W || retire.insn ==? MRET)
                resv_valid <= 1'b0;
            else if (retire.insn ==? LR_W) begin
                resv_valid <= 1'b1;
                resv_addr  <= access_addr[WIDTH-1:DADDR_START];
            end
        end

    // Values of the cycle before the rising edge; also the register writes of the debugger.
    always @(posedge clk) begin
        if (rst_n && retire.valid) begin
`ifndef VERILATOR
            if ($isunknown(retire))
                $fatal(1, "Mig3: X or Z in retire: %h", retire);
`endif
            if (halted)
                $fatal(1, "Mig3: instruction at %h retired after halt", retire_pc);
            if (retired == 0 && retire_pc !== MIG3_CFG.rst_addr)
                $fatal(1, "Mig3: first instruction at %h, expected reset address %h",
                       retire_pc, MIG3_CFG.rst_addr);
            if (expect_sequential && retired > 0 && retire_pc !== prev_pc + 4)
                $fatal(1, "Mig3: pc %h after %h, expected %h", retire_pc, prev_pc, prev_pc + 4);
            if (retire.insn !== mem_word(1'b1, retire_pc))
                $fatal(1, "Mig3: insn %h at pc %h, imem has %h",
                       retire.insn, retire_pc, mem_word(1'b1, retire_pc));
            if (retire.order !== {32'b0, retired})
                $fatal(1, "Mig3: order %0d at pc %h, expected %0d",
                       retire.order, retire_pc, retired);
            if (retired > 0 && retire_pc !== prev_pc_wdata)
                $fatal(1, "Mig3: pc %h, the instruction before (at %h) gave next pc %h",
                       retire_pc, prev_pc, prev_pc_wdata);
            check_read(retire.rs1_addr, retire.rs1_rdata);
            check_read(retire.rs2_addr, retire.rs2_rdata);
            if (mem_kind(retire.insn) == MEM_SC && !retire.trap)
                check_sc();
            else if (mem_kind(retire.insn) != MEM_NONE && !retire.trap)
                check_access();
            else if (retire.mem_rmask != 0 || retire.mem_wmask != 0)
                $fatal(1, "Mig3: pc %h is not a load or store (or trapped), but has a memory access",
                       retire_pc);
            if (retire.mem_rmask != 0 &&
                !dmem_has(retire.mem_addr, retire.mem_rmask, retire.mem_rdata))
                $fatal(1, "Mig3: load at pc %h from %h mask %b got %h, dmem has %h",
                       retire_pc, retire.mem_addr, retire.mem_rmask, retire.mem_rdata,
                       mem_word(1'b0, retire.mem_addr));
            if (retire.mem_wmask != 0)
                retired_stores.push_back('{pc: retire_pc, addr: retire.mem_addr,
                                           mask: retire.mem_wmask, data: retire.mem_wdata});
            if (retire.trap && !allow_trap)
                $fatal(1, "Mig3: trap at pc %h", retire_pc);
            if (retire.trap) begin
                traps <= traps + 1;
                if (retire.insn == INSN_EBREAK)
                    ebreak_trapped <= 1'b1;
            end
            if (trace_fd != 0) begin
                $fwrite(trace_fd, "%8d pc=%h insn=%h", cycle, retire_pc, retire.insn);
                if (retire.rd_addr != 0)
                    $fwrite(trace_fd, " x%0d <= %h", retire.rd_addr, retire.rd_wdata);
                if (retire.mem_rmask != 0)
                    $fwrite(trace_fd, " mem[%h] r %h mask %b",
                            retire.mem_addr, retire.mem_rdata, retire.mem_rmask);
                if (retire.mem_wmask != 0)
                    $fwrite(trace_fd, " mem[%h] w %h mask %b",
                            retire.mem_addr, retire.mem_wdata, retire.mem_wmask);
                if (retire.trap)
                    $fwrite(trace_fd, " trap");
                $fwrite(trace_fd, "\n");
            end
            if (retire.rd_addr != 0) begin
                shadow[retire.rd_addr]  <= retire.rd_wdata;
                written[retire.rd_addr] <= 1'b1;
            end
            prev_pc       <= retire_pc;
            prev_pc_wdata <= retire.pc_wdata;
            retired       <= retired + 1;
        end
        if (halt && dbg_req.reg_wr && dbg_req.reg_id != 0) begin
            if (trace_fd != 0)
                $fdisplay(trace_fd, "%8d debug x%0d <= %h",
                          cycle, dbg_req.reg_id, dbg_req.reg_wdata);
            shadow[dbg_req.reg_id]  <= dbg_req.reg_wdata;
            written[dbg_req.reg_id] <= 1'b1;
        end else if (halt && dbg_req.resume && trace_fd != 0)
            $fdisplay(trace_fd, "%8d resume", cycle);
        if (rst_n && dmem_write(dmem_taken))
            dmem_writes.push_back(dmem_taken);
        match_stores();
    end

    initial begin
        expect_sequential = $test$plusargs("expect_sequential");
        retired           = 0;
        traps             = 0;
        ebreak_trapped    = 1'b0;
        written           = '0;
        prev_pc           = '0;
        prev_pc_wdata     = '0;
    end

endmodule
