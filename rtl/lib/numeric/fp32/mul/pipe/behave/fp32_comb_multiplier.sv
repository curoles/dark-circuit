// Standard IEEE-754 Single Precision Layout
typedef struct packed {
    logic        sign;
    logic [7:0]  exp;
    logic [22:0] mant;
} fp32_t;

// Struct for Stage 1 -> Stage 2 internal data path (No Reset)
typedef struct packed {
    logic [47:0] prod_mant;
    logic        sign_out;
    logic [7:0]  exp_a;
    logic [7:0]  exp_b;
} stage1_data_t;

module Fp32PipelinedMultiplier #(
    localparam int WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n, // Active-low reset (Control paths only)
    input  wire  [WIDTH-1:0]     a,
    input  wire  [WIDTH-1:0]     b,
    output logic [WIDTH-1:0]     result
);

    // STAGE 1: Unpacking & Mantissa Multiply
    fp32_t float_a, float_b;
    assign float_a = fp32_t'(a);
    assign float_b = fp32_t'(b);

    wire [23:0] mant_a = {1'b1, float_a.mant};
    wire [23:0] mant_b = {1'b1, float_b.mant};

    // Instantiate our pipeline structs and signals
    stage1_data_t r1_data;
    logic         r1_is_zero;

    // Data Path: Free-running, packs perfectly into hardware DSPs
    always_ff @(posedge clk) begin
        r1_data.prod_mant <= mant_a * mant_b;
        r1_data.sign_out  <= float_a.sign ^ float_b.sign;
        r1_data.exp_a     <= float_a.exp;
        r1_data.exp_b     <= float_b.exp;
    end

    // Control Path: Strictly managed by reset
    always_ff @(posedge clk) begin
        if (!rst_n) r1_is_zero <= 1'b0;
        else        r1_is_zero <= (float_a.exp == 8'd0) || (float_b.exp == 8'd0);
    end


    // STAGE 2: Exponent Addition & Normalization
    logic [8:0] exp_sum_raw;
    fp32_t      norm_out;

    // Pulling parameters cleanly straight out of our Stage 1 data struct
    // stored_exp=true_exp + 127, so we do 127*2 - 127 = 127
    assign exp_sum_raw = r1_data.exp_a + r1_data.exp_b - 8'd127;

    always_comb begin
        norm_out.sign = r1_data.sign_out;
        
        // If MSB (bit 47) is 1, overflow happened -> Shift left & adjust exponent
        if (r1_data.prod_mant) begin
            norm_out.exp  = exp_sum_raw[7:0] + 1'b1;
            norm_out.mant = r1_data.prod_mant[46:24];
        end 
        // No overflow (bit 46 is the leading 1)
        else begin
            norm_out.exp  = exp_sum_raw[7:0];
            norm_out.mant = r1_data.prod_mant[45:23];
        end
    end

    // --- Data Path: Stage 2 Register ---
    fp32_t r2_float_out;
    always_ff @(posedge clk) begin
        r2_float_out <= norm_out; // Clean structural assignment
    end

    // --- Control Path: Stage 2 Register ---
    logic  r2_is_zero;
    always_ff @(posedge clk) begin
        if (!rst_n) r2_is_zero <= 1'b0;
        else        r2_is_zero <= r1_is_zero;
    end


    // STAGE 3: Clean Final Output Selection
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            result <= '0;
        end else begin
            if (r2_is_zero) begin
                result <= '0; 
            end else begin
                result <= WIDTH'(r2_float_out); // Cast back to raw bit vector
            end
        end
    end

endmodule
