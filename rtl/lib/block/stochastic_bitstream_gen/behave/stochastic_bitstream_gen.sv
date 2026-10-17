// MODULE: Stochastic Bitstream Generator with Configurable LFSR
// 
// FUNCTION: 
//   Converts a standard binary integer input into a 1-bit stochastic stream. 
//   The percentage density of 1s appearing on the output wire over time is perfectly 
//   proportional to the magnitude of the binary input value.
//
// NON-STANDARD PARADIGM:
//   This block is the fundamental building block of Stochastic Computing architectures.
//   By converting binary data into time-encoded bit probabilities, complex arithmetic 
//   like multiplication can be executed later using a single logic gate (e.g., an AND gate).
// =======================================================================================

module StochasticBitstreamGen #(
    parameter WIDTH = 8  // Configurable template bit-width (e.g., 4, 8, 16, 32)
)(
    input  wire               clk,        // System Clock
    input  wire               rst_n,      // Reset (Active Low)
    input  wire [WIDTH-1:0]   binary_in,  // Static binary value to convert (0 to 2^WIDTH - 1)
    output reg                stream_out  // 1-bit Probabilistic / Stochastic stream output
);

    // Internal wire to carry the pseudo-random uniform threshold from the LFSR
    wire [WIDTH-1:0] lfsr_rand;


    // ===================================================================================
    // STEP 1: DIGITAL COMPARATOR LOGIC
    // 
    // MATHEMATICAL PRINCIPLE:
    //   The LFSR acts as a uniform noise source, visiting every number between 1 and 2^WIDTH-1
    //   exactly once per full cycle. By comparing our target binary input to this moving
    //   uniform value, the comparator will output a '1' exactly 'binary_in - 1' times.
    //
    //   Example for WIDTH=8, binary_in = 128 (Midpoint of the spectrum):
    //   The condition (128 > lfsr_rand) will evaluate to True 127 times out of 255 states.
    //   Measured Output Probability = 127 / 255 = 49.8% (representing roughly 0.5)
    // ===================================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            stream_out <= 1'b0;
        end else begin
            // If the target binary value is greater than the current random number,
            // fire a 1. Otherwise, fire a 0. This creates the temporal probability stream.
            stream_out <= (binary_in > lfsr_rand);
        end
    end


    // ===================================================================================
    // STEP 2: GALOIS LFSR INSTANTIATION
    // 
    //   This module implements a Maximal-Period Linear Feedback Shift Register.
    //   It uses a compile-time function to automatically pick the correct hardware 
    //   polynomial logic based on whatever WIDTH parameter you pass to the template.
    // ===================================================================================
    Lfsr #(.WIDTH(WIDTH)) u_lfsr (
        .clk   (clk),
        .rst_n (rst_n),
        .q     (lfsr_rand)
    );

endmodule

