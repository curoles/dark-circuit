/* Simple clock generator to use in RTL simulations.
 *
 * clk starts at 0 and toggles every HALF_PERIOD.
 *
 * @author    Igor Lesik
 * @copyright 2012 Igor Lesik, MIT License
 */
module SimClkGen #(
    parameter HALF_PERIOD = 1,  // clk toggles every HALF_PERIOD
    parameter DEBUG       = 0
)(
    output reg clk
);
    //localparam PERIOD = 2 * HALF_PERIOD;

    integer count;

    initial begin
        clk = 0;
        count = 0;
        forever begin
            #HALF_PERIOD clk = ~clk;
            count += 1;
            if (DEBUG)
                $display("%5d tick", count);
        end
    end

endmodule
