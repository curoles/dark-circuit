/* Test of Dec8b10b, with its halves Dec6b5b and Dec4b3b: every 10-bit value at both running
 * disparities (2048 inputs; Icarus, slow on the decoder's searches, at RD- only). The valid codes come from Enc8b10b (tested against the standard
 * in test/block/line_code/enc_8b10b): every valid input at RD- and RD+, 536 codes, no code
 * twice at one running disparity. A code of the running disparity given must decode to the
 * byte sent, with the encoder's running disparity after it and no error (the round trip); a
 * code only of the other running disparity must set disp_err alone and still give the byte;
 * any other value must set code_err alone. rd_out, for every input, is the standard's rule on
 * the bits received, computed here on its own: +1 with more ones or for 000111 / 0011, -1
 * with more zeros or for 111000 / 1100, else as before, per sub-block. Stops at the first
 * mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbDec8b10b;
`ifdef VERILATOR
    localparam N_RD = 2;            // every value at RD- and RD+
`else
    localparam N_RD = 1;            // Icarus: at RD- only
`endif
    localparam N_INPUTS = 1024 * N_RD;

    logic [7:0] enc_data;
    logic       enc_k;
    logic       enc_rd;
    wire  [9:0] enc_code;
    wire        enc_rd_out;
    wire        enc_k_err;
    logic [9:0] code;
    logic       rd_in;
    wire  [7:0] data;
    wire        k;
    wire        rd_out;
    wire        code_err;
    wire        disp_err;

    Enc8b10b u_enc_8b10b(.data(enc_data), .k(enc_k), .rd_in(enc_rd), .code(enc_code),
                         .rd_out(enc_rd_out), .k_err(enc_k_err));
    Dec8b10b u_dec_8b10b(.code, .rd_in, .data, .k, .rd_out, .code_err, .disp_err);

    // The valid codes at each running disparity: {k, data} and the running disparity after.
    logic       valid    [2][1024];
    logic [8:0] byte_of  [2][1024];
    logic       rd_after [2][1024];

    // The standard's rule for the running disparity after a sub-block of n bits.
    function automatic logic rule(input logic rd, input logic [5:0] s, input integer n);
        integer ones;
        ones = $countones(s);
        if (2 * ones != n)
            return 2 * ones > n;
        if (n == 6 && (s == 6'b000111 || s == 6'b111000))
            return s == 6'b000111;
        if (n == 4 && (s[3:0] == 4'b0011 || s[3:0] == 4'b1100))
            return s[3:0] == 4'b0011;
        return rd;
    endfunction

    // The rule on a code as received (bit 0 first: a b c d e i f g h j).
    function automatic logic rd_rule(input logic rd, input logic [9:0] c);
        logic [5:0] six;
        logic [3:0] four;
        for (int i = 0; i < 6; i++)
            six[5 - i] = c[i];
        for (int i = 0; i < 4; i++)
            four[3 - i] = c[6 + i];
        return rule(rule(rd, six, 6), {2'b00, four}, 4);
    endfunction

    integer     n_codes;
    integer     n_valid;
    integer     n_disp;
    integer     n_code;
    logic       r;

    initial begin
        // The valid codes, from the encoder.
        n_codes = 0;
        for (int i = 0; i < 2; i++)
            for (int c = 0; c < 1024; c++)
                valid[i][c] = 1'b0;
        for (int i = 0; i < 1024; i++) begin
            enc_data = 8'(i);
            enc_k    = i[8];
            enc_rd   = i[9];
            #1;
            if (!enc_k_err) begin
                if (valid[enc_rd][enc_code])
                    $fatal(1, "code %b twice at RD%s: %h and %s %h", enc_code,
                           enc_rd ? "+" : "-", byte_of[enc_rd][enc_code],
                           enc_k ? "K" : "D", enc_data);
                valid[enc_rd][enc_code]    = 1'b1;
                byte_of[enc_rd][enc_code]  = {enc_k, enc_data};
                rd_after[enc_rd][enc_code] = enc_rd_out;
                n_codes = n_codes + 1;
            end
        end
        if (n_codes != 536)
            $fatal(1, "%0d valid codes from the encoder, expected 536", n_codes);

        // Every value at both running disparities (Icarus: at RD- only, about 1 s).
        n_valid = 0;
        n_disp  = 0;
        n_code  = 0;
        for (int i = 0; i < N_INPUTS; i++) begin
            code  = 10'(i);
            rd_in = i[10];
            r     = !rd_in;
            #1;
            if (rd_out !== rd_rule(rd_in, code))
                $fatal(1, "code %b at RD%s: rd_out %b, the rule gives %b", code,
                       rd_in ? "+" : "-", rd_out, rd_rule(rd_in, code));
            if (valid[rd_in][code]) begin
                n_valid = n_valid + 1;
                if ({k, data} !== byte_of[rd_in][code] || code_err !== 1'b0 ||
                    disp_err !== 1'b0 || rd_out !== rd_after[rd_in][code])
                    $fatal(1, "code %b at RD%s: %s %h rd %b err %b %b, expected %h rd %b",
                           code, rd_in ? "+" : "-", k ? "K" : "D", data, rd_out, code_err,
                           disp_err, byte_of[rd_in][code], rd_after[rd_in][code]);
            end else if (valid[r][code]) begin
                n_disp = n_disp + 1;
                if ({k, data} !== byte_of[r][code] || code_err !== 1'b0 || disp_err !== 1'b1)
                    $fatal(1, "code %b at RD%s (a code of RD%s): %s %h err %b %b, expected %h 0 1",
                           code, rd_in ? "+" : "-", r ? "+" : "-", k ? "K" : "D", data,
                           code_err, disp_err, byte_of[r][code]);
            end else begin
                n_code = n_code + 1;
                if (code_err !== 1'b1 || disp_err !== 1'b0)
                    $fatal(1, "code %b at RD%s (no code): err %b %b, expected 1 0", code,
                           rd_in ? "+" : "-", code_err, disp_err);
            end
        end
        if (n_valid != 268 * N_RD)      // 268 valid codes at each running disparity
            $fatal(1, "%0d valid inputs, expected %0d", n_valid, 268 * N_RD);
        $display("PASS: %0d valid codes, %0d disparity errors, %0d code errors", n_valid,
                 n_disp, n_code);
        $finish;
    end
endmodule
