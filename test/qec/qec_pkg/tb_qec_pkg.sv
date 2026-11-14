/* Test of QecPkg: the layout of the rotated surface code is a code of distance d.
 *
 * For d = 3, 5, 7, 9 (up to 7 on Icarus) and both types, from the table of which stabilizer
 * touches which data qubit (touches(), once per pair): count (stabs(d) stabilizers in raster
 * order, none after them), weight (every stabilizer touches 4 data qubits inside and 2 on
 * the edge), watched (every data qubit touched by 1 or 2 stabilizers of each type, so every
 * single error is seen), commute (every X-type and Z-type stabilizer share an even number of
 * data qubits: the checks can all be measured together), logical (X errors on a whole column
 * flip no Z-type outcome, Z errors on a whole row no X-type one: the logical operators, d
 * errors). Checks named with DC_TEST_FAIL. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbQecPkg;
    import QecPkg::*;

    `DC_TEST_MUTANT_HOOK(top)

`ifdef VERILATOR
    localparam D_MAX = 9;
`else
    localparam D_MAX = 7;
`endif
    localparam NS_MAX = (D_MAX * D_MAX - 1) / 2;
    localparam NQ_MAX = D_MAX * D_MAX;

    // support[t][k][q]: stabilizer k of type t touches data qubit q, for the d being checked
    // (unpacked: Icarus indexes only those by variables).
    logic [NQ_MAX-1:0] support [2][NS_MAX];

    // The ones in v.
    function automatic int ones(logic [NQ_MAX-1:0] v);
        int n;
        n = 0;
        for (int i = 0; i < NQ_MAX; i++)
            n += int'(v[i]);
        return n;
    endfunction

    task automatic check_layout(int d);
        int ns;
        int n;
        int i;
        int j;
        ns = stabs(d);
        for (int ti = 0; ti < 2; ti++)
            for (int k = 0; k < NS_MAX; k++) begin
                logic [NQ_MAX-1:0] s;
                s = '0;
                for (int q = 0; q < d * d; q++)
                    s[q] = k < ns && touches(d, stab_e'(ti), k, q / d, q % d);
                support[ti][k] = s;
            end
        for (int ti = 0; ti < 2; ti++) begin
            n = 0;
            for (int pi = 0; pi <= d; pi++)
                for (int pj = 0; pj <= d; pj++)
                    n += int'(is_stab(d, stab_e'(ti), pi, pj));
            if (n != ns || stab_row(d, stab_e'(ti), ns) != -1)
                `DC_TEST_FAIL(count, $sformatf("d=%0d type %0d: %0d stabilizers, expected %0d",
                                               d, ti, n, ns))
            for (int k = 0; k < ns; k++) begin
                i = stab_row(d, stab_e'(ti), k);
                j = stab_col(d, stab_e'(ti), k);
                n = ones(support[ti][k]);
                if (!is_stab(d, stab_e'(ti), i, j) ||
                    n != ((i == 0 || i == d || j == 0 || j == d) ? 2 : 4))
                    `DC_TEST_FAIL(weight, $sformatf(
                        "d=%0d type %0d: %0d at (%0d, %0d): weight %0d", d, ti, k, i, j, n))
            end
            for (int q = 0; q < d * d; q++) begin
                logic [NQ_MAX-1:0] s;
                n = 0;
                for (int k = 0; k < ns; k++) begin
                    s = support[ti][k];
                    n += int'(s[q]);
                end
                if (n < 1 || n > 2)
                    `DC_TEST_FAIL(watched, $sformatf(
                        "d=%0d type %0d: data qubit %0d in %0d stabilizers", d, ti, q, n))
            end
        end
        for (int kx = 0; kx < ns; kx++)
            for (int kz = 0; kz < ns; kz++) begin
                n = ones(support[STAB_X][kx] & support[STAB_Z][kz]);
                if (n % 2 != 0)
                    `DC_TEST_FAIL(commute, $sformatf(
                        "d=%0d: X-type %0d and Z-type %0d share %0d data qubits", d, kx, kz, n))
            end
        for (int line = 0; line < d; line++) begin
            logic [NQ_MAX-1:0] column;          // X errors on column line
            logic [NQ_MAX-1:0] row;             // Z errors on row line
            column = '0;
            row    = '0;
            for (int m = 0; m < d; m++) begin
                column[m * d + line] = 1'b1;
                row[line * d + m]    = 1'b1;
            end
            for (int k = 0; k < ns; k++)
                if (ones(support[STAB_Z][k] & column) % 2 != 0 ||
                    ones(support[STAB_X][k] & row) % 2 != 0)
                    `DC_TEST_FAIL(logical, $sformatf(
                        "d=%0d: line %0d is seen by stabilizer %0d", d, line, k))
        end
    endtask

    initial begin
        for (int d = 3; d <= D_MAX; d += 2)
            check_layout(d);
        $display("PASS");
        $finish;
    end
endmodule
