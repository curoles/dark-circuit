import uvm_pkg::*;
`include "uvm_macros.svh"

class Tester extends uvm_component;

    `uvm_component_utils(Tester)

    virtual JtagBfm _jtag_bfm;

    virtual ApbBfm#(
        .ADDR_WIDTH(5),
        .WDATA_WIDTH(32),
        .RDATA_WIDTH(32),
        .NR_SLAVES(1)
    ) _apb_bfm;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    function void build_phase(uvm_phase phase);
        if(!uvm_config_db #(virtual JtagBfm)::get(null, "*", "_jtag_bfm", _jtag_bfm))
            $fatal(1, "Failed to get JTAG BFM");
        if(!uvm_config_db #(virtual ApbBfm)::get(null, "*", "_apb_bfm", _apb_bfm))
            $fatal(1, "Failed to get APB BFM");
    endfunction: build_phase

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        //bfm.up_down = 1;
        //bfm.count_en = 1;
        //bfm.send_reset();
        repeat(128) @(posedge _apb_bfm.clk);
        //$display("after 128 clocks UP counter is:%d", bfm.out_val);
        phase.drop_objection(this);
    endtask: run_phase

endclass
