module Scoreboard #(
    parameter WIDTH = 64
)(
    Alu1Bfm bfm
);

    always @(posedge bfm.clk) begin: scoreboard
        bit [WIDTH-1:0] result;
        #1;
        case (bfm.op)
        ALU1_OP_TRANSFER:   result = bfm.alu_in1;
        ALU1_OP_INC:        result = bfm.alu_in1 + 1;
        ALU1_OP_ADD:        result = bfm.alu_in1 + bfm.alu_in2;
        ALU1_OP_ADD_PLUS1:  result = bfm.alu_in1 + bfm.alu_in2 + 1;
        ALU1_OP_SUB_MINUS1: result = bfm.alu_in1 - bfm.alu_in2 - 1;
        ALU1_OP_SUB:        result = bfm.alu_in1 - bfm.alu_in2;
        ALU1_OP_DEC:        result = bfm.alu_in1 - 1;
        ALU1_OP_TRANSFER2:  result = bfm.alu_in1;
        ALU1_OP_AND:        result = bfm.alu_in1 & bfm.alu_in2;
        ALU1_OP_OR:         result = bfm.alu_in1 | bfm.alu_in2;
        ALU1_OP_XOR:        result = bfm.alu_in1 ^ bfm.alu_in2;
        ALU1_OP_NOT:        result = ~bfm.alu_in1;
        endcase

        if (bfm.alu_out != result)
            $error("FAILED: in1: %0h  in2: %0h  op: %s result: %0h vs %0h",
                bfm.alu_in1, bfm.alu_in2, bfm.op.name(), bfm.alu_out, result);
    end: scoreboard

endmodule: Scoreboard
