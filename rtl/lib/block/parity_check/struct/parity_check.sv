/* Parity check: the parities of chosen subsets of the input bits, H times in over GF(2);
 * made of gates.
 *
 * Same ports and syndrome as the behave version. Per row an And2 keeps the bits the row
 * chooses and a Parity gate XORs them:
 *
 *   in, h[r] --> And2 --> chosen bits --> Parity --> syndrome[r]
 *
 * With h tied to constants the And2s fold away and every row is an XOR tree of its chosen
 * bits, log2 of the row's ones deep.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module ParityCheck #(
    parameter ROWS = 4,                         // checks
    parameter COLS = 8                          // input bits
)(
    input  wire [ROWS-1:0][COLS-1:0] h,         // h[r][c]: check r looks at bit c
    input  wire [COLS-1:0]           in,
    output wire [ROWS-1:0]           syndrome   // syndrome[r]: parity of in on row r
);
    `DC_STATIC_ASSERT(a_sizes, ROWS >= 1 && COLS >= 1)

    // @kb: rtl/lib/block/parity_check/design
    for (genvar r = 0; r < ROWS; r++) begin : g_row
        wire [COLS-1:0] chosen;                 // in & h[r]

        And2   #(COLS) u_and2(.in1(in), .in2(h[r]), .out(chosen));
        Parity #(COLS) u_parity(.in(chosen), .parity(syndrome[r]));
    end

endmodule
