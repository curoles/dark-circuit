/* Mig3 load/store unit: data memory requests of loads and stores.
 *
 * addr is the byte address rs1 + imm (Mig3Alu). A load or a store sends its request to
 * dmem in EX. A store writes there: the bytes of rs2 are repeated over the word and wstrb
 * selects the bytes at addr. A load's word comes 1 or more clocks later, in MEM/WB, where
 * Mig3LoadData takes the loaded value from it. valid=0 sends nothing (Mig3Core: a load in
 * MEM/WB waits, one dmem request in flight).
 * misaligned=1 when the address is not aligned to the access size (LW, SW: 4 bytes;
 * LH, LHU, SH: 2): nothing is read or written, the instruction must not complete. The byte
 * in the word (offset: alignment, strobes) is rs1[1:0] + imm[1:0], added here: the low bits
 * of a sum depend only on the low bits of the operands, so the trap does not wait for the
 * adder and result mux of Mig3Alu; addr, the same sum, gives the word address.
 * mem describes the access for the retire trace (RVFI): bytes read or written; the word
 * read is added in MEM/WB. dmem_req also carries the byte and the size of the access, so
 * an uncached one reaches memory or a device exactly. cancel=1 (an SC that fails,
 * Mig3Atomic) does not do the store: no request, no write in mem; a misaligned SC still
 * traps.
 *
 * Mig3Core instantiates it in EX, for the instruction in EX. In: addr is the result of
 * Mig3Alu, rs1_data and rs2_data come from the ID/EX register. Out: dmem_req goes straight out of
 * Mig3Core to data memory (SimLatencyRAM in Mig3Cpu); misaligned goes to Mig3Control, which
 * makes it a misaligned load or store trap with mtval = addr; mem goes into the retire
 * entry. The loaded word comes back from dmem in MEM/WB, where Mig3LoadData picks its
 * bytes by the offset and funct3 that EX/MEM carries.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig3Lsu import Mig3Pkg::*, RiscvPkg::*; (
    input  wire              valid,      // instruction in EX is valid
    // Of dec only mem, funct3 and the low bits of imm are used, of rs1_data the low bits, of
    // addr the word address.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t         dec,
    input  word_t            rs1_data,   // base address
    input  word_t            addr,       // rs1 + imm, from Mig3Alu
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t            rs2_data,   // store data
    input  wire              cancel,     // the store is not done: an SC that fails
    output dmem_req_t       dmem_req,
    output wire              misaligned, // address not aligned to the access size: a fault
    output lsu_mem_t         mem         // access for the retire trace
);
    // Parts of the address and of the store data.
    byte_offset_t           offset;     // byte in the word
    logic                   odd;        // odd byte address
    logic [7:0]             rs2_b;
    logic [15:0]            rs2_h;
    // @kb: rtl/design/mig2/narrow_local_compute
    // @kb: rtl/design/mig2/lsu_own_offset
    assign offset = rs1_data[DADDR_START-1:0] + dec.imm[DADDR_START-1:0];
    assign odd    = offset[0];
    assign rs2_b  = rs2_data[7:0];
    assign rs2_h  = rs2_data[15:0];

    logic  load;
    logic  store;       // a store, also one that is cancelled (it may be misaligned)
    logic  write;       // a store that writes: not cancelled
    logic  unaligned;   // offset is not aligned to the size of funct3
    word_t wr_data;
    strb_t strb;        // bytes of the access: size of funct3 at offset
    strb_t strb_b;      // strobes of a byte at offset 0
    strb_t strb_h;      // strobes of a halfword at offset 0
    size_t size;        // bytes of the access: 1 << size
    assign strb_b = {{(STRB_WIDTH - 1){1'b0}}, 1'b1};
    assign strb_h = {{(STRB_WIDTH - 2){1'b0}}, 2'b11};

    assign load  = valid && dec.mem.read;
    assign store = valid && dec.mem.write;
    assign write = store && !cancel;

    always_comb
        case (dec.funct3)
            F3_H, F3_HU: unaligned = odd;
            F3_W:        unaligned = offset != '0;
            default:     unaligned = 1'b0;      // bytes
        endcase

    assign misaligned = (load || store) && unaligned;

    // Bytes of the access; loads and stores have the same funct3 sizes (B, H, W).
    always_comb
        case (dec.funct3)
            F3_B, F3_BU: strb = strb_b << offset;
            F3_H, F3_HU: strb = strb_h << offset;
            default:     strb = '1;
        endcase

    always_comb
        case (dec.funct3)
            F3_B, F3_BU: size = SIZE_B;
            F3_H, F3_HU: size = SIZE_H;
            default:     size = SIZE_W;
        endcase

    // Store: bytes of rs2 repeated over the word, strobes select the bytes at offset.
    always_comb
        case (dec.funct3)
            F3_B:    wr_data = {STRB_WIDTH{rs2_b}};
            F3_H:    wr_data = {(STRB_WIDTH / 2){rs2_h}};
            default: wr_data = rs2_data;
        endcase

    assign dmem_req.valid = (load || write) && !misaligned;
    assign dmem_req.we    = write;
    assign dmem_req.addr   = addr[WIDTH-1:DADDR_START];
    assign dmem_req.offset = offset;
    assign dmem_req.size   = size;
    assign dmem_req.wdata = wr_data;
    assign dmem_req.wstrb = strb;
    assign dmem_req.atop  = AtomicPkg::ATOP_NONE;     // no AMOs yet

    // Access for the retire trace, 0 for other instructions and misaligned addresses.
    assign mem.addr  = (load || store) ? {addr[WIDTH-1:DADDR_START], {DADDR_START{1'b0}}} : '0;
    assign mem.rmask = (load && !misaligned) ? strb : '0;
    assign mem.wmask = (write && !misaligned) ? strb : '0;
    assign mem.wdata = (write && !misaligned) ? wr_data : '0;

endmodule
