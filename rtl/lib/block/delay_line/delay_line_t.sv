/* Delay line of type T: DelayLine with WIDTH = $bits(T); out is in, DEPTH clocks later. RESET = 1
 * resets the stages to 0. Behave or struct version, whichever DelayLine the flist has.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module DelayLineT #(
    parameter type T     = logic [7:0],         // type of the value
    parameter      DEPTH = 1,                   // clocks; 0: out = in
    parameter      RESET = 0                    // 1: the stages reset to 0
)(
    input  wire clk,
    input  wire rst_n,                          // synchronous reset, active low
    input  T    in,
    output T    out
);
    DelayLine #(.WIDTH($bits(T)), .DEPTH(DEPTH), .RESET(RESET)) u_delay_line(
        .clk, .rst_n, .in, .out);

endmodule
