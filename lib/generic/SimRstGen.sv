/**@file
 * @brief  Simple reset signal generator to use in RTL simulations.
 * @author Igor Lesik 2012
 */

module SimRstGen #(
    parameter TIMEOUT = 1
)(
    input  wire  clk,
    output reg   rst
);

integer count = TIMEOUT;

initial
begin
    rst = 0;
end

always @(posedge clk)
begin
    count += 1;
    if (count > TIMEOUT)
        rst <= 1;
    else
        rst <= 0;
end

endmodule
