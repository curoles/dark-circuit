/* Rising edge D Flip Flop with asynchronous clear, TSMC-style cell DFCNQ.
 *
 * Define DARK_CIRCUIT_BUILTIN_UDP to use Verilog user-defined primitive,
 * otherwise always_ff is used.
 */
`ifdef DARK_CIRCUIT_BUILTIN_UDP
// BLKSEQ warnings at UDP table rows come from how Verilator translates UDP.
/* verilator lint_off BLKSEQ */
primitive UDP_DFCNQ (Q, D, CP, CDN);
    output Q;
    reg    Q;
    input  D, CP, CDN;
    table
    //  D  CP    CDN   : Q : Q+
        ?  ?     0     : ? : 0;  // clear
        ?  ?     (?1)  : ? : -;  // release of clear
        0  (01)  1     : ? : 0;
        1  (01)  1     : ? : 1;
        ?  (?0)  ?     : ? : -;
        ?  (1x)  ?     : ? : -;
        *  ?     ?     : ? : -;
    endtable
endprimitive
/* verilator lint_on BLKSEQ */
`endif

module DFCNQ (
    input  wire D,
    input  wire CP,  // clock
    input  wire CDN, // clear, active low
    output wire Q
);

`ifdef DARK_CIRCUIT_BUILTIN_UDP
    UDP_DFCNQ u_dfcnq(Q, D, CP, CDN);
`else
    reg q_r;
    always_ff @(posedge CP or negedge CDN)
        if (!CDN)
            q_r <= 1'b0;
        else
            q_r <= D;
    assign Q = q_r;
`endif

endmodule
