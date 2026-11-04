/* The 3b/4b half of the 8b/10b line code (IEEE 802.3 clause 36; Widmer and Franaszek),
 * behavioral: the high three bits y (HGF) of a byte D.x.y or K.x.y to the 4-bit part fghj of
 * its code, at the running disparity after the 6-bit part (from Enc5b6b).
 *
 * The table and its rule for RD+ are LineCodePkg's (shared with the decoder). A .7 data code is
 * D.x.P7, or D.x.A7 when Enc5b6b says alt7.
 *
 *   y, k, alt7, rd_in --> code4 (LineCodePkg) --> fghj --> rd_after4 --> rd_out
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
    // @kb: rtl/lib/block/line_code/enc_8b10b/design
    assign fghj   = LineCodePkg::code4(y, k, alt7, rd_in);
    assign rd_out = LineCodePkg::rd_after4(fghj, rd_in);

endmodule
