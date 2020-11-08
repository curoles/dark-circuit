/* 2-input NAND.
 *
 *
 * <script type="WaveDrom">
 * { assign:[
 *   ["out",
 *     ["~&", "in1", "in2"]
 *   ]
 * ]}
 * </script>
 * 
 * <pre>
 *    ---------+-------------+------ vdd
 *             |             |
 *       +--o| p1      +--o| p2
 *       |     |       |     |
 *       |     +-------------+------ out
 *       |             |     |
 *  in1 -+-----------------| n1
 *                     |     |
 *  in2 ---------------+---| n2
 *                           |
 *                   --------+------ gnd
 * </pre>
 */
module NAnd2 (
    input  wire in1,
    input  wire in2,
    output wire out
);

    supply1 vdd;
    supply0 gnd;

    wire w_n; // connects 2 nmos transistors

    // pmos drain source gate
    pmos p1(out,  vdd,   in1);
    pmos p2(out,  vdd,   in2);

    // nmos drain source gate
    nmos n1(out,  w_n,   in1);
    nmos n2(w_n,  gnd,   in2);

endmodule
