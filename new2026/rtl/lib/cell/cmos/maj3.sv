/* CMOS 3-input Majority, TSMC-style cell MAJ3.
 *
 * ~Z = ~((A1 & A2) | (A3 & (A1 | A2))) = AOI22(A1, A2, A3, OR2(A1, A2)),
 * then inverter.
 *
 * TODO: revisit cmos MAJ3: there is a simpler transistor-level form,
 * the carry stage of the classic "mirror adder". It's 10 transistors
 * that compute ~MAJ in one stage, then an inverter, so 12 in total:
 * - pull-down (nmos): (A1-A2 in series) in parallel with (A3 in series with (A1 || A2))
 * - pull-up (pmos): the same structure with pmos. It's "mirrored": for majority
 *   the same topology works for both networks, because majority is self-dual.
 */
module MAJ3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);
    wire a12_or, z_n;

    OR2   u_or2  (.A1(A1), .A2(A2), .Z(a12_or));
    AOI22 u_aoi22(.A1(A1), .A2(A2), .B1(A3), .B2(a12_or), .ZN(z_n));
    INV   u_inv  (.I(z_n), .ZN(Z));

endmodule
