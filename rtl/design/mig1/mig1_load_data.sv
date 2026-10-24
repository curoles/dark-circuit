/* Mig1 load data: the loaded value from the dmem word.
 *
 * word is the dmem word of the load; offset is the byte of the address in the word.
 * load_data is the bytes at offset, sign- or zero-extended by funct3 (LB, LH, LW, LBU,
 * LHU; RiscvPkg F3_*). Combinational.
 *
 * Mig1Core instantiates it in MEM/WB, where dmem's word arrives one clock after the read
 * request that Mig1Lsu sent in EX. funct3 and offset come from the EX/MEM register: EX
 * puts them there with the load. load_data is the load's rd value: the register file
 * writes it at the end of MEM/WB, Mig1Forward forwards it to the instruction in ID (a
 * load right before it waits one cycle, see Mig1Control), and the retire trace shows it.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig1LoadData import Mig1Pkg::*, RiscvPkg::*; (
    input  funct3_t                funct3,
    input  byte_offset_t           offset,     // byte in the word
    input  word_t                  word,       // dmem word of the load
    output word_t                  load_data
);
    // The word shifted so the bytes at offset are at bit 0, its low byte and halfword,
    // and their sign bits.
    word_t       shifted;
    logic [7:0]  shifted_b;
    logic [15:0] shifted_h;
    logic        sign_b;
    logic        sign_h;
    assign shifted   = word >> {offset, 3'b000};
    assign shifted_b = shifted[7:0];
    assign shifted_h = shifted[15:0];
    assign sign_b    = shifted_b[7];
    assign sign_h    = shifted_h[15];

    always_comb
        case (funct3)
            F3_B:    load_data = {{(WIDTH - 8){sign_b}},  shifted_b};
            F3_H:    load_data = {{(WIDTH - 16){sign_h}}, shifted_h};
            F3_BU:   load_data = {{(WIDTH - 8){1'b0}},    shifted_b};
            F3_HU:   load_data = {{(WIDTH - 16){1'b0}},   shifted_h};
            default: load_data = shifted;               // LW
        endcase

endmodule
