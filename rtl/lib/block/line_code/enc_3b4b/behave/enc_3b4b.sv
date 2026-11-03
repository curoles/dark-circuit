/* The 3b/4b half of the 8b/10b line code (IEEE 802.3 clause 36; Widmer and Franaszek),
 * behavioral: the high three bits y (HGF) of a byte D.x.y or K.x.y to the 4-bit part fghj of
 * its code, at the running disparity after the 6-bit part (from Enc5b6b).
 *
 * The table is the standard's column for running disparity -1 (RD-), data and control codes
 * side by side, written as the standard writes them (f first, so f is bit 3 here). The column
 * for RD+ follows from one rule: a code with one or three ones (disparity -2 or +2) is sent
 * complemented at RD+; so is D.x.3 (1100, balanced), and so is every control code's part (the
 * K column holds, for y = 1, 2, 5, 6, the complements of the balanced data codes, so that a
 * comma ends with the right bits). Every other code is balanced, sent as it is, and keeps the
 * running disparity. A .7 data code is D.x.P7 (1110), or D.x.A7 (0111) when Enc5b6b says alt7,
 * against runs of five equal bits.
 *
 *   {k, y}, alt7 --> table (RD- column) --> neg --> XOR flip --> fghj
 *   flip   = rd_in AND (ones(neg) != 2 OR y == 3 OR k)
 *   rd_out = rd_in XOR (ones(neg) != 2)
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Enc3b4b (
    input  wire [2:0] y,        // HGF: the high three bits of the byte
    input  wire       k,        // a control code: the K column
    input  wire       alt7,     // a .7 data code is sent as D.x.A7 (from Enc5b6b)
    input  wire       rd_in,    // running disparity after the 6-bit part: 0 = -1, 1 = +1
    output wire [3:0] fghj,     // the 4-bit part as the standard writes it: f is bit 3
    output wire       rd_out    // running disparity after it
);
    logic [3:0] neg;            // the code at RD-
    wire        unbalanced;     // one or three ones: the running disparity changes
    wire        flip;           // sent complemented: RD+ and a code that alternates

    // The standard's 3b/4b table, column RD-: data codes, then control codes; the RD+ column
    // is the rule below.
    // @kb: rtl/lib/block/line_code/enc_8b10b/design
    always_comb
        case ({k, y})
            4'b0_000: neg = 4'b1011;
            4'b0_001: neg = 4'b1001;
            4'b0_010: neg = 4'b0101;
            4'b0_011: neg = 4'b1100;
            4'b0_100: neg = 4'b1101;
            4'b0_101: neg = 4'b1010;
            4'b0_110: neg = 4'b0110;
            4'b0_111: neg = alt7 ? 4'b0111 : 4'b1110;   // D.x.A7 : D.x.P7
            4'b1_000: neg = 4'b1011;
            4'b1_001: neg = 4'b0110;
            4'b1_010: neg = 4'b1010;
            4'b1_011: neg = 4'b1100;
            4'b1_100: neg = 4'b1101;
            4'b1_101: neg = 4'b0101;
            4'b1_110: neg = 4'b1001;
            default:  neg = 4'b0111;                    // K.x.7
        endcase

    assign unbalanced = $countones(neg) != 2;
    assign flip       = rd_in && (unbalanced || y == 3'd3 || k);
    assign fghj       = neg ^ {4{flip}};
    assign rd_out     = rd_in ^ unbalanced;

endmodule
