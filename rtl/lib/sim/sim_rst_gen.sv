/* Simple reset signal generator to use in RTL simulations.
 *
 * rst_n is 0 (reset is active) at the first CYCLES rising edges of clk,
 * it becomes 1 right after the CYCLES-th rising edge.
 *
 * @author    Igor Lesik
 * @copyright 2012 Igor Lesik, MIT License
 */
module SimRstGen #(
    parameter CYCLES = 1   // reset is active during first CYCLES rising clock edges
)(
    input  wire clk,
    output reg  rst_n      // active low
);
    integer count;

    initial begin
        rst_n = 0;
        count = 0;
    end

    always @(posedge clk) begin
        if (count < CYCLES)
            count <= count + 1;
        if (count >= CYCLES - 1)
            rst_n <= 1;
    end

endmodule
