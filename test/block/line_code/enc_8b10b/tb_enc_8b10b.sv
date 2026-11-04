/* Test of Enc8b10b, with its halves Enc5b6b and Enc3b4b: every byte, data and control, at both
 * running disparities. Every valid input (256 data and 12 control codes, at RD- and RD+: 536)
 * is checked three ways: against a model that takes both columns of the standard's tables (the
 * RTL keeps only the RD- column and derives the other), against the rules of the code (five
 * ones and the running disparity kept, or four or six ones and the other one), and, for a few,
 * against codes written out from the standard. k with any other byte must set k_err, a valid
 * input must not. Then a stream of codes (Verilator 20000, Icarus 5000), random data and now
 * and then K.28.5, each at the running disparity the one before left: no run of more than
 * five equal bits, and a comma (0011111 or 1100000) exactly where a K.28.5 starts, nowhere
 * else. Checks named with DC_TEST_FAIL (model, rules, k_err, count, known, run, comma,
 * commas); stops at the first mismatch. Mutants: kb test/block/line_code/enc_8b10b/mutants.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbEnc8b10b;
`ifdef VERILATOR
    localparam N_STREAM = 20000;
`else
    localparam N_STREAM = 5000;     // Icarus: about 1 s
`endif

    logic [7:0] data;
    logic       k;
    logic       rd_in;
    wire  [9:0] code;
    wire        rd_out;
    wire        k_err;

    Enc8b10b u_enc_8b10b(.data, .k, .rd_in, .code, .rd_out, .k_err);
    `DC_TEST_MUTANT_HOOK(top)

    // The standard's 5b/6b table, both columns (abcdei as written, a first).
    function automatic logic [5:0] six(input logic [4:0] x, input logic kc, input logic rd);
        logic [5:0] n, p;
        case (x)
            5'd0:  begin n = 6'b100111; p = 6'b011000; end
            5'd1:  begin n = 6'b011101; p = 6'b100010; end
            5'd2:  begin n = 6'b101101; p = 6'b010010; end
            5'd3:  begin n = 6'b110001; p = n;         end
            5'd4:  begin n = 6'b110101; p = 6'b001010; end
            5'd5:  begin n = 6'b101001; p = n;         end
            5'd6:  begin n = 6'b011001; p = n;         end
            5'd7:  begin n = 6'b111000; p = 6'b000111; end
            5'd8:  begin n = 6'b111001; p = 6'b000110; end
            5'd9:  begin n = 6'b100101; p = n;         end
            5'd10: begin n = 6'b010101; p = n;         end
            5'd11: begin n = 6'b110100; p = n;         end
            5'd12: begin n = 6'b001101; p = n;         end
            5'd13: begin n = 6'b101100; p = n;         end
            5'd14: begin n = 6'b011100; p = n;         end
            5'd15: begin n = 6'b010111; p = 6'b101000; end
            5'd16: begin n = 6'b011011; p = 6'b100100; end
            5'd17: begin n = 6'b100011; p = n;         end
            5'd18: begin n = 6'b010011; p = n;         end
            5'd19: begin n = 6'b110010; p = n;         end
            5'd20: begin n = 6'b001011; p = n;         end
            5'd21: begin n = 6'b101010; p = n;         end
            5'd22: begin n = 6'b011010; p = n;         end
            5'd23: begin n = 6'b111010; p = 6'b000101; end
            5'd24: begin n = 6'b110011; p = 6'b001100; end
            5'd25: begin n = 6'b100110; p = n;         end
            5'd26: begin n = 6'b010110; p = n;         end
            5'd27: begin n = 6'b110110; p = 6'b001001; end
            5'd28: begin n = 6'b001110; p = n;         end
            5'd29: begin n = 6'b101110; p = 6'b010001; end
            5'd30: begin n = 6'b011110; p = 6'b100001; end
            default: begin n = 6'b101011; p = 6'b010100; end
        endcase
        if (kc && x == 5'd28) begin
            n = 6'b001111;
            p = 6'b110000;
        end
        return rd ? p : n;
    endfunction

    // The standard's 3b/4b table, both columns (fghj as written, f first).
    function automatic logic [3:0] four(input logic [2:0] y, input logic kc, input logic a7,
                                        input logic rd);
        logic [3:0] n, p;
        case ({kc, y})
            4'b0_000: begin n = 4'b1011; p = 4'b0100; end
            4'b0_001: begin n = 4'b1001; p = n;       end
            4'b0_010: begin n = 4'b0101; p = n;       end
            4'b0_011: begin n = 4'b1100; p = 4'b0011; end
            4'b0_100: begin n = 4'b1101; p = 4'b0010; end
            4'b0_101: begin n = 4'b1010; p = n;       end
            4'b0_110: begin n = 4'b0110; p = n;       end
            4'b0_111: if (a7) begin n = 4'b0111; p = 4'b1000; end
                      else    begin n = 4'b1110; p = 4'b0001; end
            4'b1_000: begin n = 4'b1011; p = 4'b0100; end
            4'b1_001: begin n = 4'b0110; p = 4'b1001; end
            4'b1_010: begin n = 4'b1010; p = 4'b0101; end
            4'b1_011: begin n = 4'b1100; p = 4'b0011; end
            4'b1_100: begin n = 4'b1101; p = 4'b0010; end
            4'b1_101: begin n = 4'b0101; p = 4'b1010; end
            4'b1_110: begin n = 4'b1001; p = 4'b0110; end
            default:  begin n = 4'b0111; p = 4'b1000; end
        endcase
        return rd ? p : n;
    endfunction

    // A code as the standard writes it (abcdei fghj, a first) to the order it is sent in.
    function automatic logic [9:0] sent(input logic [9:0] written);
        logic [9:0] s;
        for (int i = 0; i < 10; i++)
            s[i] = written[9 - i];
        return s;
    endfunction

    // The running disparity after a block: +1 with more ones, -1 with more zeros, else kept.
    function automatic logic rd_after(input logic rd, input integer ones, input integer half);
        return ones == half ? rd : ones > half;
    endfunction

    // The model: the 6-bit part at rd, the 4-bit part at the disparity after it; a .7 data
    // code takes A7 where the standard says (x = 17, 18, 20 at RD-; 11, 13, 14 at RD+).
    task automatic model(input logic [7:0] d, input logic kc, input logic rd,
                         output logic [9:0] c, output logic rd_end);
        logic [4:0] x;
        logic [2:0] y;
        logic [5:0] s;
        logic [3:0] f;
        logic       rd6;
        logic       a7;
        x      = d[4:0];
        y      = d[7:5];
        s      = six(x, kc, rd);
        rd6    = rd_after(rd, $countones(s), 3);
        a7     = rd6 ? (x == 11 || x == 13 || x == 14) : (x == 17 || x == 18 || x == 20);
        f      = four(y, kc, a7, rd6);
        rd_end = rd_after(rd6, $countones(f), 2);
        c      = sent({s, f});
    endtask

    function automatic logic valid_k(input logic [7:0] d);
        return d[4:0] == 5'd28 ||
               (d[7:5] == 3'd7 && (d[4:0] == 5'd23 || d[4:0] == 5'd27 || d[4:0] == 5'd29 ||
                                   d[4:0] == 5'd30));
    endfunction

    task automatic apply(input logic [7:0] d, input logic kc, input logic rd);
        data  = d;
        k     = kc;
        rd_in = rd;
        #1;
    endtask

    // A few codes written out from the standard (abcdei fghj).
    task automatic known(input logic [7:0] d, input logic kc, input logic rd,
                         input logic [9:0] written, input string name);
        apply(d, kc, rd);
        if (code !== sent(written))
            `DC_TEST_FAIL(known, $sformatf("%s at RD%s: code %b (a first), expected %b", name,
                                           rd ? "+" : "-", sent(code), written))
    endtask

    integer     n_valid;
    integer     n_kerr;
    integer     n_k285;
    integer     n_comma;
    integer     run;
    integer     n_bits;
    logic [9:0] exp_code;
    logic       exp_rd;
    logic [6:0] window;         // the last seven bits sent, the oldest in bit 6
    logic       last;
    logic       is_k285;

    initial begin
        // Every input.
        n_valid = 0;
        n_kerr  = 0;
        for (int i = 0; i < 1024; i++) begin
            apply(8'(i), i[8], i[9]);
            if (k && !valid_k(data)) begin
                n_kerr = n_kerr + 1;
                if (k_err !== 1'b1)
                    `DC_TEST_FAIL(k_err, $sformatf("K byte %h: k_err %b, expected 1", data,
                                                   k_err))
            end else begin
                n_valid = n_valid + 1;
                model(data, k, rd_in, exp_code, exp_rd);
                if (k_err !== 1'b0 || code !== exp_code || rd_out !== exp_rd)
                    `DC_TEST_FAIL(model, $sformatf(
                        "%s byte %h at RD%s: code %b rd %b k_err %b, expected %b %b 0",
                        k ? "K" : "D", data, rd_in ? "+" : "-", code, rd_out, k_err,
                        exp_code, exp_rd))
                if (!(($countones(code) == 5 && rd_out == rd_in) ||
                      ($countones(code) == 6 && !rd_in && rd_out) ||
                      ($countones(code) == 4 && rd_in && !rd_out)))
                    `DC_TEST_FAIL(rules, $sformatf(
                        "%s byte %h at RD%s: %0d ones and RD%s after: not a valid code",
                        k ? "K" : "D", data, rd_in ? "+" : "-", $countones(code),
                        rd_out ? "+" : "-"))
            end
        end
        if (n_valid != 536 || n_kerr != 488)
            `DC_TEST_FAIL(count, $sformatf(
                "inputs: %0d valid, %0d with k_err; expected 536 and 488", n_valid, n_kerr))

        known(8'hBC, 1'b1, 1'b0, 10'b001111_1010, "K.28.5");
        known(8'hBC, 1'b1, 1'b1, 10'b110000_0101, "K.28.5");
        known(8'hFC, 1'b1, 1'b0, 10'b001111_1000, "K.28.7");
        known(8'hB5, 1'b0, 1'b0, 10'b101010_1010, "D.21.5");
        known(8'h00, 1'b0, 1'b0, 10'b100111_0100, "D.0.0");
        known(8'hF1, 1'b0, 1'b0, 10'b100011_0111, "D.17.7 (A7)");
        known(8'hEB, 1'b0, 1'b1, 10'b110100_1000, "D.11.7 (A7)");
        known(8'hF7, 1'b1, 1'b0, 10'b111010_1000, "K.23.7");

        // A stream, each code at the running disparity the one before left.
        rd_in   = 1'b0;
        n_k285  = 0;
        n_comma = 0;
        n_bits  = 0;
        run     = 0;
        window  = '0;
        last    = 1'b0;
        for (int s = 0; s < N_STREAM; s++) begin
            is_k285 = ($urandom % 16) == 0;
            apply(is_k285 ? 8'hBC : 8'($urandom), is_k285, rd_in);
            n_k285 = n_k285 + (is_k285 ? 1 : 0);
            for (int b = 0; b < 10; b++) begin
                run    = (n_bits > 0 && code[b] == last) ? run + 1 : 1;
                last   = code[b];
                window = {window[5:0], code[b]};
                n_bits = n_bits + 1;
                if (run > 5)
                    `DC_TEST_FAIL(run, $sformatf(
                        "stream code %0d (byte %h, k %b): a run of %0d equal bits", s, data,
                        k, run))
                if (n_bits >= 7 && (window == 7'b0011111 || window == 7'b1100000)) begin
                    if (!(is_k285 && b == 6))
                        `DC_TEST_FAIL(comma, $sformatf(
                            "stream code %0d (byte %h, k %b): a comma ending at bit %0d", s,
                            data, k, b))
                    n_comma = n_comma + 1;
                end
            end
            rd_in = rd_out;
        end
        if (n_comma != n_k285 || n_k285 == 0)
            `DC_TEST_FAIL(commas, $sformatf("stream: %0d commas for %0d K.28.5", n_comma,
                                            n_k285))
        $display("PASS: %0d valid inputs, %0d with k_err, a stream of %0d codes with %0d commas",
                 n_valid, n_kerr, N_STREAM, n_comma);
        $finish;
    end
endmodule
