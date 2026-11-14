/* Test of ParityCheck, behave or struct version.
 *
 * Model: every syndrome bit by counting the ones in and h's row share, unlike either
 * version. Every configuration gets random matrices; some get a known one besides: KIND 1
 * Hamming(7,4) (one flipped bit p must give syndrome p: hamming), KIND 2 the Z-type
 * stabilizers of a surface code (QecPkg: a single X error must give its 1 or 2 stabilizers,
 * a column of X errors none: qec), KIND 3 the identity (syndrome = in). Inputs are
 * exhaustive up to 10 bits, else random: 2000 per matrix on Verilator, 60 on Icarus.
 * Checks named with DC_TEST_FAIL: model, hamming, qec. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbParityCheckCheck #(
    parameter ROWS = 3,
    parameter COLS = 7,
    parameter KIND = 0,                 // 0 random only, 1 Hamming(7,4), 2 QEC, 3 identity
    parameter D    = 3                  // KIND 2: the distance (ROWS, COLS from it)
)(
    output logic done
);
    import QecPkg::*;

`ifdef VERILATOR
    localparam N_RANDOM = 2000;
`else
    localparam N_RANDOM = 60;
`endif
    localparam EXHAUSTIVE = COLS <= 10;
    localparam WORDS      = (COLS + 31) / 32;   // 32-bit words of a random row

    logic [ROWS-1:0][COLS-1:0] h;
    logic [COLS-1:0]           in;
    wire  [ROWS-1:0]           syndrome;
    integer                    seed;

    ParityCheck #(.ROWS(ROWS), .COLS(COLS)) u_parity_check(.h, .in, .syndrome);

    // Random bits, 32 at a time.
    function automatic logic [COLS-1:0] random_row();
        // The bits above COLS are not used.
        /* verilator lint_off UNUSEDSIGNAL */
        logic [WORDS*32-1:0] r;
        /* verilator lint_on UNUSEDSIGNAL */
        for (int i = 0; i < WORDS; i++)
            r[32*i +: 32] = $random(seed);
        return r[COLS-1:0];
    endfunction

    // The ones in s.
    function automatic int ones(logic [ROWS-1:0] s);
        int n;
        n = 0;
        for (int i = 0; i < ROWS; i++)
            n += int'(s[i]);
        return n;
    endfunction

    task automatic check;
        logic [ROWS-1:0] exp;
        for (int r = 0; r < ROWS; r++) begin
            logic [COLS-1:0] row;
            int              n;
            row = h[r];
            n   = 0;
            for (int c = 0; c < COLS; c++)
                n += int'(row[c] && in[c]);
            exp[r] = n % 2 == 1;
        end
        #1;
        if (syndrome !== exp)
            `DC_TEST_FAIL(model, $sformatf(
                "ParityCheck %0dx%0d: h %h in %h: syndrome %b, expected %b", ROWS, COLS, h, in,
                syndrome, exp))
    endtask

    // Every input (or random ones) with the matrix in h.
    task automatic all_inputs;
        if (EXHAUSTIVE)
            for (int x = 0; x < (1 << COLS); x++) begin
                in = COLS'(x);
                check();
            end
        else
            for (int i = 0; i < N_RANDOM; i++) begin
                in = random_row();
                check();
            end
    endtask

    initial begin
        done = 1'b0;
        seed = ROWS * 100 + COLS;
        for (int m = 0; m < 3; m++) begin                   // random matrices
            for (int r = 0; r < ROWS; r++)
                h[r] = random_row();
            all_inputs();
        end
        if (KIND == 1) begin                                // Hamming(7,4)
            for (int r = 0; r < ROWS; r++) begin
                logic [COLS-1:0] row;
                for (int c = 0; c < COLS; c++)
                    row[c] = ((c + 1) >> r) % 2 == 1;
                h[r] = row;
            end
            all_inputs();
            for (int p = 1; p <= COLS; p++) begin
                in = COLS'(1) << (p - 1);
                #1;
                if (int'(syndrome) != p)
                    `DC_TEST_FAIL(hamming, $sformatf("bit %0d flipped: syndrome %0d", p,
                                                     syndrome))
            end
        end else if (KIND == 2) begin                       // the Z-type stabilizers of D
            for (int r = 0; r < ROWS; r++) begin
                logic [COLS-1:0] row;
                for (int c = 0; c < COLS; c++)
                    row[c] = touches(D, STAB_Z, r, c / D, c % D);
                h[r] = row;
            end
            all_inputs();
            for (int q = 0; q < COLS; q++) begin            // a single X error
                in = COLS'(1) << q;
                #1;
                if (ones(syndrome) < 1 || ones(syndrome) > 2)
                    `DC_TEST_FAIL(qec, $sformatf("D=%0d: X error at %0d: syndrome %b", D, q,
                                                 syndrome))
            end
            for (int col = 0; col < D; col++) begin         // a column: the logical X
                in = '0;
                for (int r = 0; r < D; r++)
                    in[r * D + col] = 1'b1;
                #1;
                if (syndrome !== '0)
                    `DC_TEST_FAIL(qec, $sformatf("D=%0d: column %0d of X errors: syndrome %b",
                                                 D, col, syndrome))
            end
        end else if (KIND == 3) begin                       // the identity
            for (int r = 0; r < ROWS; r++)
                h[r] = COLS'(1) << r;
            all_inputs();
        end
        done = 1'b1;
    end
endmodule

module TbParityCheck;
    `DC_TEST_MUTANT_HOOK(top)

    wire done_1, done_7, done_9, done_25, done_8, done_33, done_64;

    TbParityCheckCheck #(.ROWS(1),  .COLS(1))                    u_check_1 (.done(done_1));
    TbParityCheckCheck #(.ROWS(3),  .COLS(7),  .KIND(1))         u_check_7 (.done(done_7));
    TbParityCheckCheck #(.ROWS(4),  .COLS(9),  .KIND(2), .D(3))  u_check_9 (.done(done_9));
    TbParityCheckCheck #(.ROWS(12), .COLS(25), .KIND(2), .D(5))  u_check_25(.done(done_25));
    TbParityCheckCheck #(.ROWS(8),  .COLS(8),  .KIND(3))         u_check_8 (.done(done_8));
    TbParityCheckCheck #(.ROWS(5),  .COLS(33))                   u_check_33(.done(done_33));
    TbParityCheckCheck #(.ROWS(16), .COLS(64))                   u_check_64(.done(done_64));

    initial begin
        wait (done_1 && done_7 && done_9 && done_25 && done_8 && done_33 && done_64);
        $display("PASS");
        $finish;
    end
endmodule
