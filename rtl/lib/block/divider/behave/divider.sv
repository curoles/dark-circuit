/* Divider: quotient and remainder of unsigned integers, one quotient bit per clock
 * (restoring division), behavioral.
 *
 * Author: Igor Lesik
 *
 * start=1 while busy=0 takes dividend and divisor on the rising edge; then busy=1 for
 * WIDTH clocks, and done=1 for one clock in the last of them (its last step): after
 * that clock, with busy=0 again, quotient and remainder are valid and stay until the
 * next start. start while busy is ignored.
 * Every clock shifts the next dividend bit into the partial remainder and subtracts
 * the divisor if it fits (quotient bit 1). Dividing by 0 gives quotient all ones and
 * remainder = dividend: the divisor always fits. rst_n=0 stops a division.
 */
module Divider #(
    parameter WIDTH = 32
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
            q     <= dividend;
            r     <= '0;
            count <= STEPS;
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
