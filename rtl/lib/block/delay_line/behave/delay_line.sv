/* Delay line, behavioral: out is in, DEPTH clocks later.
 *
 * DEPTH stages of WIDTH bits; DEPTH = 0 is a wire (out = in, no clock). RESET = 1: reset makes
 * every stage RST_VAL, so out is RST_VAL until the first value after reset comes through (for
 * valid bits); RESET = 0: no reset (data, which means nothing while it is not valid).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module DelayLine #(
    parameter             WIDTH   = 1,
    parameter             DEPTH   = 1,          // clocks; 0: out = in
    parameter             RESET   = 0,          // 1: the stages reset to RST_VAL
    parameter [WIDTH-1:0] RST_VAL = '0
)(
    // clk is not used when DEPTH is 0, rst_n when RESET is 0.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire             clk,
    input  wire             rst_n,              // synchronous reset, active low
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);
    if (DEPTH == 0) begin: g_wire
        assign out = in;
    end else begin: g_stages
        logic [WIDTH-1:0] stage [DEPTH];        // stage i: in, i + 1 clocks ago

        always_ff @(posedge clk)
            if (RESET != 0 && !rst_n)
                for (int i = 0; i < DEPTH; i++)
                    stage[i] <= RST_VAL;
            else begin
                stage[0] <= in;
                for (int i = 1; i < DEPTH; i++)
                    stage[i] <= stage[i - 1];
            end

        assign out = stage[DEPTH - 1];
    end

endmodule
