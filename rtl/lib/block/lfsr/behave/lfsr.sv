module LinFeedbShiftReg #(
    parameter WIDTH = 8  // Configurable width template (e.g., 4, 8, 16, 32)
)(
    input  wire               clk,    // System clock
    input  wire               rst_n,  // Reset (Active Low)
    output reg  [WIDTH-1:0]   q       // Configurable width random output
);

    // Pure function to look up the correct Galois tap mask for a given width.
    // These masks ensure a maximal period cycle of (2^WIDTH - 1) states.
    function [31:0] get_taps(input integer w);
        case (w)
            4  : get_taps = 4'hC;          // x^4 + x^3 + 1
            8  : get_taps = 8'hB8;         // x^8 + x^6 + x^5 + x^4 + 1
            12 : get_taps = 12'hE01;       // x^12 + x^11 + x^10 + x^4 + 1
            16 : get_taps = 16'hB400;      // x^16 + x^15 + x^13 + x^11 + 1
            32 : get_taps = 32'h80000057;  // x^32 + x^22 + x^2 + x^1 + 1
            default: get_taps = 8'hB8;     // Default fallback
        endcase
    endfunction

    // Apply the function at compile-time to generate a constant tap mask
    localparam [WIDTH-1:0] TAP_MASK = get_taps(WIDTH);

    always @(posedge clk /* ASYNC or negedge rst_n*/) begin
        if (!rst_n) begin
            // Seed the register with 1s. Prevents lockup state of all 0s.
            q <= {WIDTH{1'b1}}; 
        end else begin
            // Galois shift-right logic
            if (q[0]) begin
                q <= (q >> 1) ^ TAP_MASK;
            end else begin
                q <= (q >> 1);
            end
        end
    end

endmodule
