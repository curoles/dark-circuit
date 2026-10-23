/* Commands of Alu1.
 *
 * Arithmetic (cmd[3]=0) adds in1 and S1 S0 = cmd[2:1] selected 0, in2, ~in2 or all ones,
 * with carry in cmd[0]. Logic (cmd[3]=1) is selected by cmd[1:0]; cmd 12..15 are not
 * commands, they work as 8..11.
 *
 * @author    Igor Lesik
 * @copyright 2020 Igor Lesik, MIT License
 */
package Alu1Pkg;

    localparam CMD_WIDTH   = 4;
    // For users, for example a testbench that picks a random command.
    /* verilator lint_off UNUSEDPARAM */
    localparam NR_COMMANDS = 8 + 4;
    /* verilator lint_on UNUSEDPARAM */

    typedef enum logic [CMD_WIDTH-1:0] {
        OP_TRANSFER   = 0,   // in1
        OP_INC        = 1,   // in1 + 1
        OP_ADD        = 2,   // in1 + in2
        OP_ADD_PLUS1  = 3,   // in1 + in2 + 1
        OP_SUB_MINUS1 = 4,   // in1 - in2 - 1 = in1 + ~in2
        OP_SUB        = 5,   // in1 - in2     = in1 + ~in2 + 1
        OP_DEC        = 6,   // in1 - 1       = in1 + all ones
        OP_TRANSFER2  = 7,   // in1           = in1 + all ones + 1
        OP_AND        = 8,   // in1 & in2
        OP_OR         = 9,   // in1 | in2
        OP_XOR        = 10,  // in1 ^ in2
        OP_NOT        = 11   // ~in1
    } op_e;

endpackage
