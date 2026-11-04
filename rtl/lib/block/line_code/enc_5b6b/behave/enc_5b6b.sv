/* The 5b/6b half of the 8b/10b line code (IEEE 802.3 clause 36; Widmer and Franaszek),
 * behavioral: the low five bits x (EDCBA) of a byte D.x.y to the 6-bit part abcdei of its code,
 * at the running disparity rd_in.
 *
 * The table and its rule for RD+ are LineCodePkg's (shared with the decoder). K.28 has a 6-bit
 * part of its own; the other control codes (K.23.7, K.27.7, K.29.7, K.30.7) use the data codes.
 * alt7 tells the 3b/4b half to send a .7 as D.x.A7 (the codes after which it does are balanced,
 * so the running disparity there is rd_in).
 *
 *   x, k AND x == 28, rd_in --> code6 (LineCodePkg) --> abcdei --> rd_after6 --> rd_out
 *   x, rd_in --> alt7_of --> alt7
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Enc5b6b (
    input  wire [4:0] x,        // EDCBA: the low five bits of the byte
    input  wire       k,        // a control code (only K.28 changes this half)
    input  wire       rd_in,    // running disparity before: 0 = -1, 1 = +1
    output wire [5:0] abcdei,   // the 6-bit part as the standard writes it: a is bit 5
    output wire       rd_out,   // running disparity after it
    output wire       alt7      // a .7 data code is sent as D.x.A7 (to Enc3b4b)
);
    // @kb: rtl/lib/block/line_code/enc_8b10b/design
    assign abcdei = LineCodePkg::code6(x, k && x == 5'd28, rd_in);
    assign rd_out = LineCodePkg::rd_after6(abcdei, rd_in);
    assign alt7   = LineCodePkg::alt7_of(x, rd_in);

endmodule
