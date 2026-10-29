/* Mig2 load/store unit: data memory requests of loads and stores.
 *
 * addr is the byte address rs1 + imm (Mig2Alu). A store writes in its cycle in EX:
 * the bytes of rs2 are repeated over the word and wr_strb selects the bytes at addr.
 * A load sends the read in EX; the word comes from dmem 1 clock later, in MEM/WB, where
 * Mig2LoadData takes the loaded value from it.
 * misaligned=1 when the address is not aligned to the access size (LW, SW: 4 bytes;
 * LH, LHU, SH: 2): nothing is read or written, the instruction must not complete. The byte
 * in the word (offset: alignment, strobes) is rs1[1:0] + imm[1:0], added here: the low bits
 * of a sum depend only on the low bits of the operands, so the trap does not wait for the
 * adder and result mux of Mig2Alu; addr, the same sum, gives the word address.
 * mem describes the access for the retire trace (RVFI): bytes read or written; the word
 * read is added in MEM/WB.
 *
 * Mig2Core instantiates it in EX, for the instruction in EX. In: addr is the result of
 * Mig2Alu, rs1_data and rs2_data come from the ID/EX register. Out: dmem_req goes straight out of
 * Mig2Core to data memory (SimRAM in Mig2Cpu); misaligned goes to Mig2Control, which
 * makes it a misaligned load or store trap with mtval = addr; mem goes into the retire
 * entry. The loaded word comes back from dmem in MEM/WB, where Mig2LoadData picks its
 * bytes by the offset and funct3 that EX/MEM carries.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig2Lsu import Mig2Pkg::*, RiscvPkg::*; (
    input  wire              valid,      // instruction in EX is valid
    // Of dec only mem, funct3 and the low bits of imm are used, of rs1_data the low bits, of
    // addr the word address.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t         dec,
    input  word_t            rs1_data,   // base address
    input  word_t            addr,       // rs1 + imm, from Mig2Alu
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t            rs2_data,   // store data
    output dmem_req_t        dmem_req,
    output wire              misaligned, // address not aligned to the access size: a fault
    output lsu_mem_t         mem         // access for the retire trace
);
    // Parts of the address and of the store data.
    byte_offset_t           offset;     // byte in the word
    logic                   odd;        // odd byte address
    logic [7:0]             rs2_b;
    logic [15:0]            rs2_h;
    // @kb: rtl/design/mig2/lsu_own_offset
    assign offset = rs1_data[DADDR_START-1:0] + dec.imm[DADDR_START-1:0];
    assign odd    = offset[0];
    assign rs2_b  = rs2_data[7:0];
    assign rs2_h  = rs2_data[15:0];

    logic  load;
    logic  store;
    logic  unaligned;   // offset is not aligned to the size of funct3
    word_t wr_data;
    strb_t strb;        // bytes of the access: size of funct3 at offset
    strb_t strb_b;      // strobes of a byte at offset 0
    strb_t strb_h;      // strobes of a halfword at offset 0
    assign strb_b = {{(STRB_WIDTH - 1){1'b0}}, 1'b1};
    assign strb_h = {{(STRB_WIDTH - 2){1'b0}}, 2'b11};

    assign load  = valid && dec.mem.read;
    assign store = valid && dec.mem.write;

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

    // Store: bytes of rs2 repeated over the word, strobes select the bytes at offset.
    always_comb
        case (dec.funct3)
            F3_B:    wr_data = {STRB_WIDTH{rs2_b}};
            F3_H:    wr_data = {(STRB_WIDTH / 2){rs2_h}};
            default: wr_data = rs2_data;
        endcase

    assign dmem_req.rd_en   = load && !misaligned;
    assign dmem_req.wr_en   = store && !misaligned;
    assign dmem_req.addr    = addr[WIDTH-1:DADDR_START];
    assign dmem_req.wr_data = wr_data;
    assign dmem_req.wr_strb = strb;

    // Access for the retire trace, 0 for other instructions and misaligned addresses.
    assign mem.addr  = (load || store) ? {addr[WIDTH-1:DADDR_START], {DADDR_START{1'b0}}} : '0;
    assign mem.rmask = (load && !misaligned) ? strb : '0;
    assign mem.wmask = dmem_req.wr_en ? strb : '0;
    assign mem.wdata = dmem_req.wr_en ? wr_data : '0;

endmodule
