/* Rising edge D Flip Flop, TSMC-style cell DFQ.
 *
 * Define DARK_CIRCUIT_BUILTIN_UDP to use Verilog user-defined primitive,
 * otherwise always_ff is used.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`ifdef DARK_CIRCUIT_BUILTIN_UDP
// BLKSEQ warnings at UDP table rows come from how Verilator translates UDP.
/* verilator lint_off BLKSEQ */
primitive UDP_DFQ (Q, D, CP);
    output Q;
    reg    Q;
    input  D, CP;
    table
    //  D  CP    : Q : Q+
        0  (01)  : ? : 0;
        1  (01)  : ? : 1;
        ?  (?0)  : ? : -;
        ?  (1x)  : ? : -;
        *  ?     : ? : -;
    endtable
endprimitive
/* verilator lint_on BLKSEQ */
`endif

module DFQ (
    input  wire D,
    input  wire CP, // clock
    output wire Q
);

`ifdef DARK_CIRCUIT_BUILTIN_UDP
    UDP_DFQ u_dfq(Q, D, CP);
`else
    reg q_r;
    always_ff @(posedge CP)
        q_r <= D;
    assign Q = q_r;
`endif

endmodule
