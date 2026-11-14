/* QEC: the rotated surface code of distance d, the layout every QEC block shares.
 *
 * Terms (J. Roffe, Quantum Error Correction: An Introductory Guide, Contemporary Physics
 * 60(3), 2019, arXiv:1907.11157):
 * - data qubits hold the protected information; an X error flips a qubit's bit, a Z error its
 *   phase;
 * - a stabilizer is a parity check of a few neighbouring data qubits, measured through a
 *   measure qubit without reading the data: Z-type stabilizers see X errors, X-type ones see
 *   Z errors; 1 means the parity changed (odd);
 * - the syndrome is one round of all stabilizer outcomes of a type;
 * - the distance d is the fewest errors that change the stored value unseen: d = 2t + 1
 *   corrects up to t errors.
 *
 * The layout: d x d data qubits at row r, column c (0 to d - 1), index q = r * d + c.
 * Stabilizers sit at the corners between them, plaquette (i, j) with i, j from 0 to d, and
 * touch the data qubits (i-1, j-1), (i-1, j), (i, j-1), (i, j) that exist. Inside, plaquettes
 * alternate in a checkerboard, X-type where i + j is even, Z-type where it is odd; on the edge
 * every other one remains, weight 2: X-type at the top and bottom (i = 0, d), Z-type at the
 * left and right (j = 0, d); corners have none. Each type has (d^2 - 1) / 2 stabilizers,
 * numbered in raster order of (i, j). For d = 3 (X, Z plaquettes; o data qubits):
 *
 *   plaquette j     0     1     2     3
 *   i = 0                       X
 *   data row 0         o     o     o
 *   i = 1           Z     X     Z
 *   data row 1         o     o     o
 *   i = 2                 Z     X     Z
 *   data row 2         o     o     o
 *   i = 3                 X
 *
 * X-type 0 to 3 at (0, 2), (1, 1), (2, 2), (3, 1); Z-type 0 to 3 at (1, 0), (1, 2), (2, 1),
 * (2, 3). An X error on a column of data qubits from
 * top to bottom touches every Z-type stabilizer twice or not at all: unseen, a logical X;
 * likewise Z errors on a row and the X-type ones. So d errors can be unseen, fewer not.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package QecPkg;

    typedef enum logic {
        STAB_X = 1'b0,                  // X-type: parity of the phases, sees Z errors
        STAB_Z = 1'b1                   // Z-type: parity of the bits, sees X errors
    } stab_e;

    // Data qubits of distance d.
    function automatic int data_qubits(int d);
        return d * d;
    endfunction

    // Stabilizers of each type.
    function automatic int stabs(int d);
        return (d * d - 1) / 2;
    endfunction

    // Plaquette (i, j), 0 to d each, holds a stabilizer of type t.
    // @kb: rtl/lib/qec/surface_code
    function automatic logic is_stab(int d, stab_e t, int i, int j);
        logic x;                                        // X-type in the checkerboard
        logic top_bottom;
        logic left_right;
        x          = (i + j) % 2 == 0;
        top_bottom = i == 0 || i == d;
        left_right = j == 0 || j == d;
        if (top_bottom && left_right)
            return 1'b0;                                // a corner
        else if (top_bottom)
            return t == STAB_X && x;                    // top, bottom: X-type
        else if (left_right)
            return t == STAB_Z && !x;                   // left, right: Z-type
        else
            return (t == STAB_X) == x;                  // inside: the checkerboard
    endfunction

    // The plaquette row i of stabilizer k of type t (raster order), -1 if there is none.
    // The result is kept and returned at the end: Icarus 13 crashes on a return in a loop.
    function automatic int stab_row(int d, stab_e t, int k);
        int n;
        int row;
        n   = 0;
        row = -1;
        for (int i = 0; i <= d; i++)
            for (int j = 0; j <= d; j++)
                if (is_stab(d, t, i, j)) begin
                    if (n == k)
                        row = i;
                    n++;
                end
        return row;
    endfunction

    // The plaquette column j of stabilizer k of type t, -1 if there is none.
    function automatic int stab_col(int d, stab_e t, int k);
        int n;
        int col;
        n   = 0;
        col = -1;
        for (int i = 0; i <= d; i++)
            for (int j = 0; j <= d; j++)
                if (is_stab(d, t, i, j)) begin
                    if (n == k)
                        col = j;
                    n++;
                end
        return col;
    endfunction

    // Stabilizer k of type t touches data qubit (r, c).
    function automatic logic touches(int d, stab_e t, int k, int r, int c);
        int i;
        int j;
        i = stab_row(d, t, k);
        j = stab_col(d, t, k);
        return i >= 0 && (r == i - 1 || r == i) && (c == j - 1 || c == j);
    endfunction

endpackage
