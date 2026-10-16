import uvm_pkg::*;
`include "uvm_macros.svh"

module TbTop (

);

    localparam WIDTH = 8;

    CounterBfm#(WIDTH) bfm();

    Counter#(WIDTH) counter_(
        .clk(bfm.clk),
        .rst_n(~bfm.rst),
        .load(bfm.load),
        .in(bfm.in_val),
        .up_down(bfm.up_down),
        .count_en(bfm.count_en),
        .out(bfm.out_val),
        .co(bfm.carry_out)
    );

    initial begin
        uvm_config_db #(virtual CounterBfm)::set(null, "*", "bfm", bfm);
        run_test();
    end

endmodule: TbTop
