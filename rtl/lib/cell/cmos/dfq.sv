/* CMOS Rising edge D Flip Flop, TSMC-style cell DFQ.
 *
 * Master-slave: master latch is transparent while CP is 0,
 * slave latch is transparent while CP is 1.
 */
module DFQ (
    input  wire D,
    input  wire CP, // clock
    output wire Q
);
    wire cp_n, master_q;

    INV u_inv   (.I(CP), .ZN(cp_n));
    LHQ u_master(.D(D), .E(cp_n), .Q(master_q));
    LHQ u_slave (.D(master_q), .E(CP), .Q(Q));

endmodule
