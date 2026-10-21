/* Fp32 combinational multiplier: IEEE-754 single precision a * b, behavioral.
 *
 * Multiplies the 24-bit mantissas (hidden 1 added), adds the exponents minus the bias
 * 127 and normalizes by one bit; the mantissa is truncated, not rounded. An input with
 * exponent 0 (zero or subnormal) gives 0. Infinity, NaN and exponent overflow or
 * underflow are not handled.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

// Packed struct definition for IEEE-754 Single Precision Float
typedef struct packed {
    logic        sign;
    logic [7:0]  exp;
    logic [22:0] mant;
} fp32_t;

module Fp32CombMultiplier #(
    localparam int WIDTH = 32
)(
    input  wire  [WIDTH-1:0] a,
    input  wire  [WIDTH-1:0] b,
    output logic [WIDTH-1:0] result
);

    // Cast the raw input wires into our SystemVerilog structure
    fp32_t float_a;
    fp32_t float_b;
    fp32_t float_out;

    assign float_a = fp32_t'(a);
    assign float_b = fp32_t'(b);

    // Append the implicit leading 1 to the mantissas (24 bits each)
    wire [23:0] mant_a = {1'b1, float_a.mant};
    wire [23:0] mant_b = {1'b1, float_b.mant};

    // Intermediate calculations
    logic        sign_out;
    logic [8:0]  exp_out_raw; 
    wire  [47:0] prod_mant;   

    // Multiply the 24-bit mantissas to get a 48-bit product
    assign prod_mant = mant_a * mant_b;

    always_comb begin
        // Calculate output sign via XOR
        sign_out = float_a.sign ^ float_b.sign;

        // Add exponents and subtract the 127 bias
        exp_out_raw = float_a.exp + float_b.exp - 8'd127;

        // Normalization and Result Assembly
        if (prod_mant[47]) begin
            float_out.sign = sign_out;
            float_out.exp  = exp_out_raw + 1'b1;
            float_out.mant = prod_mant[46:24]; 
        end 
        else begin
            float_out.sign = sign_out;
            float_out.exp  = exp_out_raw;
            float_out.mant = prod_mant[45:23]; 
        end

        // Cast structured output back to the raw bitstream result
        result = WIDTH'(float_out);

        // Edge case: Handle zero inputs safely
        if ((float_a.exp == 8'd0) || (float_b.exp == 8'd0)) begin
            result = '0; // SystemVerilog fill literal
        end
    end

endmodule
