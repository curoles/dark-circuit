/* Complex gate OR-AND-Invertor, TSMC-style cell OAI22.
 *
 * <pre>
 *  A1 ----------+--\
 *               )OR +----+
 *  A2 ----------+--/|    |
 *                   |NAND|o----- ZN
 *  B1 ----------+--\|    |
 *               )OR +----+
 *  B2 ----------+--/
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module OAI22 (
    input  wire A1, // to be OR-ed with A2
    input  wire A2, // to be OR-ed with A1
    input  wire B1, // to be OR-ed with B2
    input  wire B2, // to be OR-ed with B1
    output wire ZN  // NAND the results of two ORs
);

    assign ZN = ~((A1 | A2) & (B1 | B2));

endmodule
