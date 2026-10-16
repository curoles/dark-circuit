import uvm_pkg::*;
`include "uvm_macros.svh"

class Env extends uvm_env;

    `uvm_component_utils(Env)

    Tester _tester;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    function void build_phase(uvm_phase phase);
        _tester = Tester::type_id::create("_tester", this);
    endfunction: build_phase

endclass

