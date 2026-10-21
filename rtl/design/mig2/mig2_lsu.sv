/* Mig2 load/store unit: data memory requests of loads and stores.
 *
 * addr is the byte address rs1 + imm (Mig2Alu). A store writes in its cycle in EX:
 * the bytes of rs2 are repeated over the word and wr_strb selects the bytes at addr.
 * A load sends the read in EX; the word comes from dmem 1 clock later, in MEM/WB, where
 * Mig2LoadData takes the loaded value from it.
 * misaligned=1 when addr is not aligned to the access size (LW, SW: 4 bytes;
 * LH, LHU, SH: 2): nothing is read or written, the instruction must not complete.
 * mem describes the access for the retire trace (RVFI): bytes read or written; the word
 * read is added in MEM/WB.
 */
module Mig2Lsu import Mig2Pkg::*, RiscvPkg::*; (
    input  wire              valid,      // instruction in EX is valid
    // Only kind and funct3 are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t         dec,
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t            addr,
    input  word_t            rs2_data,   // store data
    output dmem_req_t        dmem_req,
    output wire              misaligned, // address not aligned to the access size: a fault
    output lsu_mem_t         mem         // access for the retire trace
);
    // Fields and bit selects with assign: Icarus warns about selects in always_comb.
    kind_t                  kind;
    logic [2:0]             funct3;
    byte_offset_t           offset;     // byte in the word
    logic                   odd;        // odd byte address
    logic [7:0]             rs2_b;
    logic [15:0]            rs2_h;
    assign kind   = dec.kind;
    assign funct3 = dec.funct3;
    assign offset = addr[DADDR_START-1:0];
    assign odd    = addr[0];
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

    assign load  = valid && kind == KIND_LOAD;
    assign store = valid && kind == KIND_STORE;

    always_comb
        case (funct3)
            F3_H, F3_HU: unaligned = odd;
            F3_W:        unaligned = offset != '0;
            default:     unaligned = 1'b0;      // bytes
        endcase

    assign misaligned = (load || store) && unaligned;

    // Bytes of the access; loads and stores have the same funct3 sizes (B, H, W).
    always_comb
        case (funct3)
            F3_B, F3_BU: strb = strb_b << offset;
            F3_H, F3_HU: strb = strb_h << offset;
            default:     strb = '1;
        endcase

    // Store: bytes of rs2 repeated over the word, strobes select the bytes at offset.
    always_comb
        case (funct3)
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
