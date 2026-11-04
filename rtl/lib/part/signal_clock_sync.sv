

module SignalClockSynch #(
    WIDTH = 1,
    STAGES = 2
)(
    input wire clk1,
    input wire clk2,
    input wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);

    `DC_STATIC_ASSERT(a_min_num_stages, STAGES >= 2)

    // if (FLOP_CLK1) shall we in case `in` alredy is DFF output?
    Dff #(.WIDTH(WIDTH)) u_clk1_dff(.clk(clk1), .in(in), .out(s0));

    //TODO for (genvar i = 0; i < STAGES
    Dff #(.WIDTH(WIDTH)) u_clk2_dff1(.clk(clk2), .in(s0), .out(s1));
    Dff #(.WIDTH(WIDTH)) u_clk2_dff1(.clk(clk2), .in(s1), .out(out));

endmodule
