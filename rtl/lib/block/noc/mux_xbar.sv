/* NoC crossbar made of multiplexers: every output takes the input its select names.
 *
 * N ports, each an input and an output; for a 2D mesh router N=5: inject/eject, north,
 * south, west, east. A crossbar is one MuxN per output, each with a select of its own:
 * out[i] = in[sel[i]]. Who drives the selects (a switch allocator: which input goes to which
 * output, at most one input per output) and whether an output is used in a cycle (valid) are
 * outside.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module NocMuxXbar #(
    parameter  N         = 5,               // ports: inputs and outputs
    parameter  WIDTH     = 8,               // bits of a port
    localparam SEL_WIDTH = $clog2(N)
)(
    input  wire [N-1:0][WIDTH-1:0]     in,
    input  wire [N-1:0][SEL_WIDTH-1:0] sel,     // sel[i]: the input of output i
    output wire [N-1:0][WIDTH-1:0]     out
);
    for (genvar i = 0; i < N; i++) begin: g_out
        MuxN #(.N(N), .WIDTH(WIDTH)) u_mux_n(.in, .sel(sel[i]), .out(out[i]));
    end

endmodule
