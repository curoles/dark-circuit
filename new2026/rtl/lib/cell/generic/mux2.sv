/* 2:1 Multiplexer, TSMC-style cell MUX2.
 *
 * Author: Igor Lesik 2014.
 *
 * <pre>
 *           +-----+
 * I1 -------| 1   |
 *           | MUX |--- Z
 * I0 -------| 0   |
 *           +--+--+
 *           S  |
 * </pre>
 */
module MUX2 (
    input  wire I0,  // selected when S is 0
    input  wire I1,  // selected when S is 1
    input  wire S,
    output wire Z
);

    assign Z = S ? I1 : I0;

endmodule
