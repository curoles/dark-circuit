/* Mig2 load data: the loaded value from the dmem word.
 *
 * word is the dmem word of the load; offset is the byte of the address in the word.
 * load_data is the bytes at offset, sign- or zero-extended by funct3 (LB, LH, LW, LBU,
 * LHU; RiscvPkg F3_*). Combinational; used where dmem data arrives (2nd cycle of a load
 * in EX now, MEM later).
 */
module Mig2LoadData import Mig2Pkg::*, RiscvPkg::*; (
    input  funct3_t                funct3,
    input  byte_offset_t           offset,     // byte in the word
    input  word_t                  word,       // dmem word of the load
    output word_t                  load_data
);
    // Bit selects with assign: Icarus warns about selects in always_comb.
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
