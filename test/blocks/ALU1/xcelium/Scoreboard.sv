import Alu1::*;

package Alu1Sb;

class Scoreboard #(parameter WIDTH = 64);

    virtual Alu1Bfm bfm;

    function new (virtual Alu1Bfm _bfm);
        bfm = _bfm;
    endfunction

    task execute();
        bit [WIDTH-1:0] result;
        forever begin//: checker
            @(posedge bfm.clk);
            #1;
            case (bfm.op)
            Alu1::OP_TRANSFER:   result = bfm.alu_in1;
            Alu1::OP_INC:        result = bfm.alu_in1 + 1;
            Alu1::OP_ADD:        result = bfm.alu_in1 + bfm.alu_in2;
            Alu1::OP_ADD_PLUS1:  result = bfm.alu_in1 + bfm.alu_in2 + 1;
            Alu1::OP_SUB_MINUS1: result = bfm.alu_in1 - bfm.alu_in2 - 1;
            Alu1::OP_SUB:        result = bfm.alu_in1 - bfm.alu_in2;
            Alu1::OP_DEC:        result = bfm.alu_in1 - 1;
            Alu1::OP_TRANSFER2:  result = bfm.alu_in1;
            Alu1::OP_AND:        result = bfm.alu_in1 & bfm.alu_in2;
            Alu1::OP_OR:         result = bfm.alu_in1 | bfm.alu_in2;
            Alu1::OP_XOR:        result = bfm.alu_in1 ^ bfm.alu_in2;
            Alu1::OP_NOT:        result = ~bfm.alu_in1;
            endcase

            if (bfm.alu_out != result)
                $error("FAILED: in1: %0h  in2: %0h  op: %s result: %0h vs %0h",
                    bfm.alu_in1, bfm.alu_in2, bfm.op.name(), bfm.alu_out, result);
        end//: checker
    endtask: execute

endclass: Scoreboard

endpackage
