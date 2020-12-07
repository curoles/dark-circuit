package Alu1Test;

import Alu1::*;

class Tester #(parameter WIDTH = 64);

    virtual Alu1Bfm bfm;

    localparam CMD_WIDTH = Alu1::CMD_WIDTH;

    function new (virtual Alu1Bfm _bfm);
        bfm = _bfm;
    endfunction

    protected function bit [CMD_WIDTH-1:0] generate_op();
        generate_op = $urandom % Alu1::NR_COMMANDS;
    endfunction

    protected function bit [WIDTH-1:0] generate_data();
        bit [2:0] zero_ones;
        zero_ones = $urandom;
        if (zero_ones == 3'b000)
            return {WIDTH{1'b0}};
        else if (zero_ones == 3'b111)
            return {WIDTH{1'b1}};
        else
            return (($urandom << WIDTH/2) | $urandom);
    endfunction: generate_data

    task execute();
        bit  [CMD_WIDTH-1:0] cmd;
        bit  [WIDTH-1:0]     in1;
        bit  [WIDTH-1:0]     in2;
        bit  [WIDTH-1:0]     result;

        $display("Testing...");
        repeat (1000) begin
            cmd = generate_op();
            in1 = generate_data();
            in2 = generate_data();
            bfm.send_op(in1, in2, Alu1::Op'(cmd), result);
        end
        $stop;
    endtask: execute

endclass: Tester


endpackage: Alu1Test
