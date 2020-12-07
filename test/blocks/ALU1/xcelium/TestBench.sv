package Alu1Tb;

import Alu1Sb::*;
import Alu1Test::*;
import Alu1Cov::*;

class TestBench;

    virtual Alu1Bfm bfm;

    Tester     tester_;
    Scoreboard scoreboard_;
    Coverage   coverage_;

    function new (virtual Alu1Bfm _bfm);
        bfm = _bfm;
    endfunction: new

    task execute();
        tester_     = new(bfm);
        scoreboard_ = new(bfm);
        coverage_   = new(bfm);

        fork
            tester_.execute();
            coverage_.execute();
            scoreboard_.execute();
        join_none
    endtask: execute

endclass: TestBench

endpackage: Alu1Tb
