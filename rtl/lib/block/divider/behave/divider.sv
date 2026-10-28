/* Divider: quotient and remainder of unsigned integers, one quotient bit per clock
 * (restoring division), behavioral.
 *
 * start=1 while busy=0 takes dividend and divisor on the rising edge; then busy=1 for
 * WIDTH clocks, and done=1 for one clock in the last of them (its last step): after
 * that clock, with busy=0 again, quotient and remainder are valid and stay until the
 * next start. start while busy is ignored.
 * EARLY_START=1 (WIDTH a power of 2): busy only for the significant bits of the dividend
 * (at least 1 clock): its leading zeros would bring 0 into the partial remainder and give
 * quotient bits 0, so the division skips them and starts at the highest set bit. A divisor
 * of 0 fits every step (quotient all ones), so with it all WIDTH steps run.
 * Every clock shifts the next dividend bit into the partial remainder and subtracts
 * the divisor if it fits (quotient bit 1). Dividing by 0 gives quotient all ones and
 * remainder = dividend: the divisor always fits. rst_n=0 stops a division.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Divider #(
    parameter WIDTH       = 32,
    parameter EARLY_START = 0           // 1: skip the leading zeros of the dividend
)(
    input  wire             clk,
    input  wire             rst_n,      // synchronous reset, active low
    input  wire             start,
    input  wire [WIDTH-1:0] dividend,
    input  wire [WIDTH-1:0] divisor,
    output wire             busy,
    output wire             done,       // 1 in the last clock of busy
    output wire [WIDTH-1:0] quotient,
    output wire [WIDTH-1:0] remainder
);
    localparam            CW    = $clog2(WIDTH + 1);
    localparam [CW-1:0]   STEPS = WIDTH[CW-1:0];
    localparam [CW-1:0]   ONE   = 1;

    logic [WIDTH-1:0] d;        // divisor
    logic [WIDTH-1:0] q;        // dividend bits not used yet, then quotient bits
    logic [WIDTH-1:0] r;        // partial remainder, smaller than d after every step
    logic [CW-1:0]    count;    // steps left
    logic [WIDTH:0]   shifted;  // r shifted left with the next dividend bit
    logic [WIDTH:0]   diff;     // shifted - d
    logic             fits;     // no borrow: d fits into shifted
    // q shifted left with the new quotient bit; its top bit has moved into shifted.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [WIDTH:0]   q_shifted;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [WIDTH-1:0] r_next;
    logic [WIDTH-1:0] q_next;
    logic [CW-1:0]    steps;    // steps of the division that starts
    logic [WIDTH-1:0] q_start;  // the dividend, with the leading zeros it skips shifted out

    // @kb: rtl/lib/block/divider/early_start
    // Early start: a leading zero of the dividend brings 0 into r, which stays 0, and nothing
    // fits it when the divisor is not 0: the step only makes a quotient bit 0. So the
    // division starts at the highest set bit: that many steps (at least one, for a dividend
    // of 0, so that done comes), the dividend shifted left by the zeros it skips.
    function automatic [CW-1:0] steps_of(input [WIDTH-1:0] x, input [WIDTH-1:0] y);
        steps_of = STEPS;
        if (EARLY_START != 0 && y != '0) begin
            steps_of = ONE;
            for (int k = 0; k < WIDTH; k++)
                if (x[k])
                    steps_of = CW'(k + 1);      // a higher bit wins
        end
    endfunction

    assign steps   = steps_of(dividend, divisor);
    assign q_start = dividend << (STEPS - steps);

    // One division step: shift the next dividend bit into r, subtract d, keep the
    // difference when it fits, shift the quotient bit into q.
    assign shifted   = {r, q[WIDTH-1]};
    assign diff      = shifted - {1'b0, d};
    assign fits      = !diff[WIDTH];
    assign q_shifted = {q, fits};
    assign q_next    = q_shifted[WIDTH-1:0];
    assign r_next    = fits ? diff[WIDTH-1:0] : shifted[WIDTH-1:0];

    always_ff @(posedge clk)
        if (!rst_n)
            count <= '0;
        else if (start && count == 0) begin
            d     <= divisor;
            q     <= q_start;
            r     <= '0;
            count <= steps;
        end else if (count != 0) begin
            r     <= r_next;
            q     <= q_next;
            count <= count - 1'b1;
        end

    assign busy      = count != 0;
    assign done      = count == 1;
    assign quotient  = q;
    assign remainder = r;

endmodule
