import uvm_pkg::*;
`include "uvm_macros.svh"

class IncTester extends uvm_component;

    `uvm_component_utils(IncTester)

    virtual CounterBfm bfm;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    function void build_phase(uvm_phase phase);
        if(!uvm_config_db #(virtual CounterBfm)::get(null, "*","bfm", bfm))
            $fatal(1, "Failed to get BFM");
    endfunction: build_phase

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        bfm.up_down = 1;
        bfm.count_en = 1;
        bfm.send_reset();
        repeat(128) @(posedge bfm.clk);
        $display("after 128 clocks UP counter is:%d", bfm.out_val);
        phase.drop_objection(this);
    endtask: run_phase

endclass
