/* Delay line, made of gates: out is in, DEPTH clocks later.
 *
 * Same ports, parameters and behavior as the behave version (see there): a chain of DEPTH
 * registers of WIDTH bits, DffSyncRst (RESET = 1, reset to RST_VAL) or Dff (RESET = 0);
 * DEPTH = 0 a wire.
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
        wire [DEPTH:0][WIDTH-1:0] stage;        // stage i: in, i clocks ago

        assign stage[0] = in;
        for (genvar i = 0; i < DEPTH; i++) begin: g_stage
            if (RESET != 0) begin: g_reset
                DffSyncRst #(.WIDTH(WIDTH), .RST_VAL(RST_VAL)) u_dff_sync_rst_stage(
                    .clk, .rst_n, .in(stage[i]), .out(stage[i + 1]));
            end else begin: g_no_reset
                Dff #(.WIDTH(WIDTH)) u_dff_stage(.clk, .in(stage[i]), .out(stage[i + 1]));
            end
        end
        assign out = stage[DEPTH];
    end

endmodule
