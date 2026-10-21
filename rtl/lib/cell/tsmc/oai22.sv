/* OR-AND-Invert, cell OAI22 mapped to TSMC library cell OAI22D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake OAI22D1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module OAI22 (
    input  wire A1,
    input  wire A2,
    input  wire B1,
    input  wire B2,
    output wire ZN
);

    OAI22D1 u_oai22(.A1(A1), .A2(A2), .B1(B1), .B2(B2), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module OAI22D1 (
    input  wire A1,
    input  wire A2,
    input  wire B1,
    input  wire B2,
    output wire ZN
);

    assign ZN = ~((A1 | A2) & (B1 | B2));

endmodule
`endif
