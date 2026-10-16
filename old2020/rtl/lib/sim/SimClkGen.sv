/**@file
 * @brief  Simple clock generator to use in RTL simulations.
 * @author Igor Lesik 2012
 */

module SimClkGen #(
    parameter PERIOD = 1,
    parameter DEBUG  = 0
)
(
    output reg clk
);

integer count = 0;

initial
begin
    clk = 0;
end

always
begin
    #PERIOD clk = ~clk;
    count += 1;
    if (DEBUG)
        $display("%5d tick", count);
end

endmodule
