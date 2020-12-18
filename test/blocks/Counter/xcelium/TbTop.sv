import uvm_pkg::*;
`include "uvm_macros.svh"

module TbTop (

);

    localparam WIDTH = 8;

    wire             clk;
    bit              rst;
    bit  [WIDTH-1:0] in_val;
    bit              load;
    bit              up_down;
    bit              count_en;
    wire [WIDTH-1:0] out_val;
    wire             carry_out;

    Counter#(WIDTH) counter_(
        .clk(clk),
        .rst_n(~rst),
        .load(),
        .in(in_val),
        .up_down(up_down),
        .count_en(count_en),
        .out(out_val),
        .co(carry_out)
    );

    SimClkGen#(.PERIOD(1)) clk_gen_(.clk(clk));

    initial begin
        //uvm_config_db #(virtual tinyalu_bfm)::set(null, "*", "bfm", bfm);
        run_test();
    end

endmodule: TbTop
