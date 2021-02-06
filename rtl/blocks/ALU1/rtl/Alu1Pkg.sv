package Alu1Pkg;


localparam CMD_WIDTH   = 4;
localparam NR_COMMANDS = 8+4;

typedef enum bit[CMD_WIDTH-1:0] {
    OP_TRANSFER   = 0,
    OP_INC        = 1,
    OP_ADD        = 2,
    OP_ADD_PLUS1  = 3,
    OP_SUB_MINUS1 = 4,
    OP_SUB        = 5,
    OP_DEC        = 6,
    OP_TRANSFER2  = 7,
    OP_AND        = 8,
    OP_OR         = 9,
    OP_XOR        = 10,
    OP_NOT        = 11
} Op;

endpackage: Alu1Pkg
