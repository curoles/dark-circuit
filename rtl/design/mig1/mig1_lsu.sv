/* Mig1 load/store unit: data memory requests of loads and stores, and loaded data.
 *
 * addr is the byte address rs1 + imm (Mig1Alu). A store writes in its cycle in EX:
 * the bytes of rs2 are repeated over the word and wr_strb selects the bytes at addr.
 * A load takes 2 cycles in EX: the first sends the read and sets lsu.stall=1, which
 * keeps the instruction in EX; in the second dmem_rsp has the word, load_data is its
 * bytes at addr, sign- or zero-extended (funct3, RiscvPkg F3_*). The instruction and
 * its registers do not change between the two cycles, so addr and funct3 are the
 * same; flop `second` tells which cycle it is.
 * lsu.misaligned=1 when addr is not aligned to the access size (LW, SW: 4 bytes;
 * LH, LHU, SH: 2): nothing is read or written, the instruction must not complete.
 * mem describes the access for the retire trace (RVFI): bytes read or written.
 */
module Mig1Lsu import Mig1Pkg::*, RiscvPkg::*; (
    input  wire              clk,
    input  wire              rst_n,      // synchronous reset, active low
    input  wire              valid,      // instruction in EX is valid
    // Only kind and funct3 are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t         dec,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [WIDTH-1:0] addr,       // word_t, see Mig1Pkg about ports
    input  logic [WIDTH-1:0] rs2_data,   // store data
    output dmem_req_t        dmem_req,
    input  dmem_rsp_t        dmem_rsp,
    output lsu_t             lsu,
    output logic [WIDTH-1:0] load_data,  // valid in the second cycle of a load
    output lsu_mem_t         mem         // access for the retire trace
);
    // Fields and bit selects with assign: Icarus warns about selects in always_comb.
    kind_t                  kind;
    logic [2:0]             funct3;
    logic [DADDR_START-1:0] offset;     // byte in the word
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
    logic  misaligned;
    logic  second;      // load is in its second cycle
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

    assign misaligned     = (load || store) && unaligned;
    assign lsu.misaligned = misaligned;
    assign lsu.stall      = load && !second && !misaligned;

    always_ff @(posedge clk)
        if (!rst_n) second <= 1'b0;
        else        second <= lsu.stall;

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

    assign dmem_req.rd_en   = lsu.stall;            // first cycle of a load
    assign dmem_req.wr_en   = store && !misaligned;
    assign dmem_req.addr    = addr[WIDTH-1:DADDR_START];
    assign dmem_req.wr_data = wr_data;
    assign dmem_req.wr_strb = strb;

    // Load: the word shifted so the bytes at offset are at bit 0, then extended.
    word_t       shifted;
    logic [7:0]  shifted_b;
    logic [15:0] shifted_h;
    logic        sign_b;
    logic        sign_h;
    assign shifted   = dmem_rsp.rd_data >> {offset, 3'b000};
    assign shifted_b = shifted[7:0];
    assign shifted_h = shifted[15:0];
    assign sign_b    = shifted_b[7];
    assign sign_h    = shifted_h[15];

    always_comb
        case (funct3)
            F3_B:    load_data = {{(WIDTH - 8){sign_b}},         shifted_b};
            F3_H:    load_data = {{(WIDTH - 16){sign_h}},        shifted_h};
            F3_BU:   load_data = {{(WIDTH - 8){1'b0}},           shifted_b};
            F3_HU:   load_data = {{(WIDTH - 16){1'b0}},          shifted_h};
            default: load_data = shifted;               // LW
        endcase

    // Access for the retire trace, 0 for other instructions and misaligned addresses.
    assign mem.addr  = (load || store) ? {addr[WIDTH-1:DADDR_START], {DADDR_START{1'b0}}} : '0;
    assign mem.rmask = (load && !misaligned) ? strb : '0;
    assign mem.wmask = dmem_req.wr_en ? strb : '0;
    assign mem.rdata = (load && !misaligned) ? dmem_rsp.rd_data : '0;
    assign mem.wdata = dmem_req.wr_en ? wr_data : '0;

endmodule
