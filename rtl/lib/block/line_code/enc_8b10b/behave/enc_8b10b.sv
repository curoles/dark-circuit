/* 8b/10b line code encoder (IEEE 802.3 clause 36; Widmer and Franaszek), behavioral: a byte
 * D.x.y (x = data[4:0], y = data[7:5]) or a control code K.x.y to its 10-bit code, at the
 * running disparity rd_in; combinational (the running disparity register is the user's:
 * rd_in <= rd_out each symbol, starting at -1).
 *
 * Enc5b6b codes x to the 6-bit part, Enc3b4b codes y to the 4-bit part at the running
 * disparity after it; Enc5b6b also tells Enc3b4b when a .7 takes the alternate code. Every code
 * has five ones (and keeps the running disparity) or four or six (and turns it), no run of
 * more than five equal bits, and the comma (0011111 or 1100000) only in K.28.1, K.28.5 and
 * K.28.7. Valid control codes: K.28.0 to K.28.7, K.23.7, K.27.7, K.29.7, K.30.7; k with any
 * other byte sets k_err, and code then means nothing. Bit order: the standard writes a code
 * abcdei fghj and sends a first, so code[0] = a ... code[5] = i, code[6] = f ... code[9] = j.
 *
 *   x, k, rd_in --> Enc5b6b --> abcdei ----------------+
 *                     |  alt7, rd_mid                  +--> a sent first --> code
 *                     v                                |
 *   y, k ---------> Enc3b4b --> fghj ------------------+
 *                     +-------> rd_out
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Enc8b10b (
    input  wire [7:0] data,     // HGFEDCBA
    input  wire       k,        // a control code K.x.y
    input  wire       rd_in,    // running disparity before: 0 = -1, 1 = +1
    output wire [9:0] code,     // sent bit 0 first: a b c d e i f g h j
    output wire       rd_out,   // running disparity after it
    output wire       k_err     // k with a byte that is no control code
);
    wire [4:0] x = data[4:0];
    wire [2:0] y = data[7:5];
    wire [5:0] abcdei;
    wire [3:0] fghj;
    wire [9:0] written;         // as the standard writes it: a is bit 9
    wire       rd_mid;          // running disparity between the halves
    wire       alt7;

    // @kb: rtl/lib/block/line_code/enc_8b10b/design
    Enc5b6b u_enc_5b6b(.x, .k, .rd_in, .abcdei, .rd_out(rd_mid), .alt7);
    Enc3b4b u_enc_3b4b(.y, .k, .alt7, .rd_in(rd_mid), .fghj, .rd_out);

    assign written = {abcdei, fghj};
    for (genvar i = 0; i < 10; i++) begin: g_sent_first
        assign code[i] = written[9 - i];
    end

    assign k_err = k && !(x == 5'd28 ||
                          (y == 3'd7 && (x == 5'd23 || x == 5'd27 || x == 5'd29 || x == 5'd30)));

endmodule
