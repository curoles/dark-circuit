/* Parity check, behavioral: the parities of chosen subsets of the input bits, H times in over
 * GF(2); combinational.
 *
 * Row r of h chooses the bits that check r looks at; syndrome[r] is the parity of in on them,
 * ^(h[r] & in): 1 when an odd number of them are 1. Over GF(2) (bits, AND multiplies, XOR
 * adds) that is the matrix H times the vector in. h is an input: tied to constants (a table
 * in a localparam) synthesis keeps only the XOR trees of the chosen bits; driven by
 * registers it is a code software can change. ROWS and COLS are 1 or more.
 *
 * For example, Hamming(7,4): column j - 1 of H is j in binary, in is the codeword (bits 1 to
 * 7 in in[0] to in[6]):
 *   h[0] = 1010101 (bits 1, 3, 5, 7), h[1] = 0110011 (2, 3, 6, 7), h[2] = 0001111 (4 to 7),
 *   each written bit 1 first; one flipped bit p gives syndrome = p.
 *
 * Uses: the syndrome of a linear code (Hamming and SECDED memory ECC, LDPC, CRC of a whole
 * word at once), its encoder (the check bits are G times the data), the final round of a
 * QEC experiment (the stabilizers' parities of the measured data qubits, H from QecPkg).
 *
 * The behave version takes every row's parity as one expression; the struct version is an
 * And2 and a Parity gate per row.
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
        assign syndrome[r] = ^(h[r] & in);
    end

endmodule
