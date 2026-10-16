import uvm_pkg::*;
`include "uvm_macros.svh"

class CounterDecTest extends uvm_test;

    `uvm_component_utils(CounterDecTest)

    DecTester tester_;
    Scoreboard scoreboard_;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    function void build_phase(uvm_phase phase);
        tester_     = new("tester_", this);
        scoreboard_ = new("scoreboard_", this);
    endfunction: build_phase

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        phase.drop_objection(this);
    endtask: run_phase

endclass
