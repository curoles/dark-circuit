package Alu1Cov;

import Alu1::*;

class Coverage #(parameter WIDTH = 64);

    virtual Alu1Bfm bfm;

    Alu1::Op op;

    // Cadence help UI: cdnshelp.
    // Add `-coverage A` to elaboration.
    // Default coverage directory with .ucd is cov_work.
    // Viewer tool: imc
    //
    covergroup op_cov;//OpCov;
        coverpoint op {
            bins arithm[] = {[Alu1::OP_TRANSFER:Alu1::OP_TRANSFER2]};
            bins logics[] = {[Alu1::OP_AND:Alu1::OP_NOT]};
        }
    endgroup

    //OpCov op_cov;
    //zeros_or_ones_on_ops c_00_FF;

    function new (virtual Alu1Bfm _bfm);
        op_cov = new();
        //c_00_FFF = new();
        bfm = _bfm;
    endfunction: new

    task execute();
        forever begin: sampling
            @(negedge bfm.clk);
            op = bfm.op;
            op_cov.sample();
            //c_00_FF.sample();
        end: sampling
    endtask: execute


endclass: Coverage

endpackage: Alu1Cov
