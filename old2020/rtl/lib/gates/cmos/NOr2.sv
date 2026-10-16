/* 2-input NOR
 *
 *
 * <script type="WaveDrom">
 * { assign:[
 *   ["out",
 *     ["~|", "in1", "in2"]
 *   ]
 * ]}
 * </script>
 *
 * <pre> 
 *              -------------+------ vdd
 *                           |
 *  in1 ---+--------------o| p1
 *         |                 |
 *  in2 -------------+----o| p2
 *         |         |       |
 *         |    +------------+------ out
 *         |    |    |       |
 *         +--| n1   +-----| n2
 *              |            |
 *           ---+------------+---- gnd
 * </pre>
 */

module NOr2 (
    input  wire in1,
    input  wire in2,
    output wire out
);

    supply1 vdd;
    supply0 gnd;

    wire w_p; // connects 2 pmos transistors

    // nmos drain source gate
    pmos n1(out,  gnd,   in1);
    pmos n2(out,  gnd,   in2);

    // pmos drain source gate
    pmos p1(w_p,  vdd,   in1);
    pmos p2(out,  w_p,   in2);

endmodule
