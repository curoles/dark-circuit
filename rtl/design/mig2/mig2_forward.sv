/* Mig2 forwarding: register values for the instruction in ID, with results that are not
 * in the register file yet.
 *
 * The register file is written at the end of MEM/WB, so the two instructions after an
 * instruction would read its rd too early. ID takes the value instead from the youngest
 * instruction that writes it: EX (ex_rd_data: ALU, link, CSR or M result) before MEM/WB
 * (mem_rd_data, also load data), else the register file. ex_rd and mem_rd are 0 when
 * the instruction writes no register; x0 is never forwarded (reads 0). A load in EX has
 * no data yet: Mig2Control holds the instruction in ID for that cycle (load-use).
 * The values go into the ID/EX register, so EX and the retire trace see them.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig2Forward import Mig2Pkg::*; (
    input  reg_id_t rs1,          // registers read in ID
    input  reg_id_t rs2,
    input  word_t   rf_rs1_data,  // register file values
    input  word_t   rf_rs2_data,
    input  reg_id_t ex_rd,        // rd written by the instruction in EX, 0: none
    input  word_t   ex_rd_data,
    input  reg_id_t mem_rd,       // rd written in MEM/WB, 0: none
    input  word_t   mem_rd_data,
    output word_t   rs1_data,
    output word_t   rs2_data
);
    assign rs1_data = (rs1 != '0 && rs1 == ex_rd)  ? ex_rd_data  :
                      (rs1 != '0 && rs1 == mem_rd) ? mem_rd_data : rf_rs1_data;
    assign rs2_data = (rs2 != '0 && rs2 == ex_rd)  ? ex_rd_data  :
                      (rs2 != '0 && rs2 == mem_rd) ? mem_rd_data : rf_rs2_data;

endmodule
