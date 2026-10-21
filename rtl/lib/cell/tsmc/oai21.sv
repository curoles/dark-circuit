/* OR-AND-Invert, cell OAI21 mapped to TSMC library cell OAI21D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake OAI21D1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module OAI21 (
    input  wire A1,
    input  wire A2,
    input  wire B,
    output wire ZN
);

    OAI21D1 u_oai21(.A1(A1), .A2(A2), .B(B), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module OAI21D1 (
    input  wire A1,
    input  wire A2,
    input  wire B,
    output wire ZN
);

    assign ZN = ~((A1 | A2) & B);

endmodule
`endif
