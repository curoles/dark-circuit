/* 8b/10b line code decoder (IEEE 802.3 clause 36; Widmer and Franaszek), behavioral: a
 * received 10-bit code, at the running disparity rd_in, to its byte D.x.y or control code
 * K.x.y; combinational (the running disparity register is the user's: rd_in <= rd_out each
 * code, starting at -1).
 *
 * Dec6b5b decodes the 6-bit part to x, Dec4b3b the 4-bit part to y; a control code is K.28's
 * 6-bit part, or K.x.7's 4-bit part (0111 or 1000) after x = 23, 27, 29 or 30, whose data
 * codes take P7. Both halves search LineCodePkg's tables, the encoder's. Whether the code is
 * valid is not a rule of its own: the byte decoded is encoded again (Enc8b10b) at rd_in, and
 * at the other running disparity. The same code at rd_in: valid. Only at the other one:
 * disp_err, the byte is still the one sent if the error is the disparity's. Neither:
 * code_err, data and k mean nothing. rd_out follows the standard's rule from the bits received
 * (LineCodePkg rd_after6, rd_after4), so it recovers by itself after an error. Bit order as
 * Enc8b10b: code[0] = a is received first.
 *
 *   code --> abcdei --> Dec6b5b --> x, k28 ----------------+--> data, k
 *        --> fghj   --> Dec4b3b --> y (at rd after abcdei) +
 *   data, k --> Enc8b10b at rd_in ----> == code ? --+--> code_err, disp_err
 *           --> Enc8b10b at NOT rd_in -> == code ? --+
 *   rd_out = rd_after4(fghj, rd_after6(abcdei, rd_in))
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Dec8b10b (
    input  wire [9:0] code,     // received bit 0 first: a b c d e i f g h j
    input  wire       rd_in,    // running disparity before: 0 = -1, 1 = +1
    output wire [7:0] data,     // HGFEDCBA
    output wire       k,        // a control code K.x.y
    output wire       rd_out,   // running disparity after it, by the standard's rule
    output wire       code_err, // no valid code at either running disparity
    output wire       disp_err  // a valid code, but of the other running disparity
);
    wire [9:0] written;         // as the standard writes it: a is bit 9
    wire [5:0] abcdei;
    wire [3:0] fghj;
    wire [4:0] x;
    wire [2:0] y;
    wire       k28;             // K.28's 6-bit part
    wire       rd_mid;          // running disparity after the 6-bit part
    wire [9:0] code_same;       // the byte decoded, encoded at rd_in
    wire [9:0] code_other;      // ... at the other running disparity
    wire       k_err_same;
    wire       k_err_other;
    wire       ok_same;         // code is the byte's at rd_in
    wire       ok_other;        // ... at the other running disparity
    // The running disparity after the code comes from the standard's rule, which also
    // holds after an error: the encoders' is not used.
    /* verilator lint_off UNUSEDSIGNAL */
    wire       rd_same;
    wire       rd_other;
    /* verilator lint_on UNUSEDSIGNAL */

    for (genvar i = 0; i < 10; i++) begin: g_received_first
        assign written[i] = code[9 - i];
    end
    assign abcdei = written[9:4];
    assign fghj   = written[3:0];
    assign rd_mid = LineCodePkg::rd_after6(abcdei, rd_in);
    assign rd_out = LineCodePkg::rd_after4(fghj, rd_mid);

    // @kb: rtl/lib/block/line_code/dec_8b10b/design
    Dec6b5b u_dec_6b5b(.abcdei, .x, .k28);
    assign k = k28 || (LineCodePkg::valid_k(x, 3'd7) &&
                       (fghj == LineCodePkg::code4(3'd7, 1'b1, 1'b0, 1'b0) ||
                        fghj == LineCodePkg::code4(3'd7, 1'b1, 1'b0, 1'b1)));
    Dec4b3b u_dec_4b3b(.fghj, .k, .rd_in(rd_mid), .y);
    assign data = {y, x};

    // Valid if the encoder sends this byte so.
    Enc8b10b u_enc_same(.data, .k, .rd_in, .code(code_same), .rd_out(rd_same),
                        .k_err(k_err_same));
    Enc8b10b u_enc_other(.data, .k, .rd_in(!rd_in), .code(code_other), .rd_out(rd_other),
                         .k_err(k_err_other));
    assign ok_same  = code_same == code && !k_err_same;
    assign ok_other = code_other == code && !k_err_other;
    assign code_err = !ok_same && !ok_other;
    assign disp_err = !ok_same && ok_other;

endmodule
