import uvm_pkg::*;
`include "uvm_macros.svh"

class Scoreboard extends uvm_component;

    `uvm_component_utils(Scoreboard)

    virtual CounterBfm bfm;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    function void build_phase(uvm_phase phase);
        if(!uvm_config_db #(virtual CounterBfm)::get(null, "*","bfm", bfm))
            $fatal(1, "Failed to get BFM");
    endfunction: build_phase

    task run_phase(uvm_phase phase);
        //shortint result;
        forever begin
            @(posedge bfm.clk);
        //    result = num of clks after reset
        end
    endtask: run_phase

endclass: Scoreboard
