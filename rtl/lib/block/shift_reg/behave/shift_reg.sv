/* Shift register with parallel load, behavioral.
 *
 * On every rising edge: srl_prl=1 shifts toward MSB, srl_in goes into bit 0;
 * srl_prl=0 loads prl_in. srl_out is bit WIDTH-1.
 * WIDTH must be 2 or more.
 */
module ShiftReg #(
    parameter WIDTH = 8                 // 2 or more
)(
    input  wire             clk,
    input  wire             srl_prl,    // 1 shifts (serial), 0 loads prl_in (parallel)
    input  wire             srl_in,     // shifted into bit 0
    input  wire [WIDTH-1:0] prl_in,
    output wire             srl_out,    // bit WIDTH-1
    output wire [WIDTH-1:0] prl_out
);
    reg [WIDTH-1:0] value;

    always_ff @(posedge clk)
        value <= srl_prl ? {value[WIDTH-2:0], srl_in} : prl_in;

    assign prl_out = value;
    assign srl_out = value[WIDTH-1];

endmodule
