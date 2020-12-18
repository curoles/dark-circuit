import uvm_pkg::*;
`include "uvm_macros.svh"

class CounterIncTest extends uvm_test;

    `uvm_component_utils(CounterIncTest)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        phase.drop_objection(this);
    endtask: run_phase

endclass
