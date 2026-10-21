/* Complex gate And-Or-Invertor, TSMC-style cell AOI22.
 *
 * <pre>
 *  A1 ----------+--\
 *               AND +----+
 *  A2 ----------+--/|    |
 *                   |NOR |o----- ZN
 *  B1 ----------+--\|    |
 *               AND +----+
 *  B2 ----------+--/
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module AOI22 (
    input  wire A1, // to be AND-ed with A2
    input  wire A2, // to be AND-ed with A1
    input  wire B1, // to be AND-ed with B2
    input  wire B2, // to be AND-ed with B1
    output wire ZN  // NOR the results of two ANDs
);

    assign ZN = ~((A1 & A2) | (B1 & B2));

endmodule
