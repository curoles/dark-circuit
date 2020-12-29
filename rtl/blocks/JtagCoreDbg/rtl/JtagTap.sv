/* JTAG device TAP.
 * Author: Igor Lesik 2020
 *
 * In JTAG, devices expose one or more test access ports (TAPs).
 * A daisy chain of TAPs is called a scan chain.
 *
 * ![scan chain](https://en.wikipedia.org/wiki/File:Jtag_chain.svg "Scan chain")
 *
 * The TAP connector pins are: 
 * - TDI: Test Data In
 * - TDO: Test Data Out
 * - TCK: Test Clock
 * - TMS: Test Mode Select
 * - TRST: Test Reset (optional)
 *
 * To use JTAG, a host is connected to the target's JTAG signals (TMS, TCK, TDI, TDO, etc.)
 * through some kind of JTAG adapter, which may need to handle issues like level shifting and galvanic isolation.
 * The adapter connects to the host using some interface such as USB, PCI, Ethernet, and so forth.
 *
 * The host communicates with the TAPs by manipulating TMS and TDI in conjunction with TCK,
 * and reading results through TDO.
 *
 * TMS/TDI/TCK transitions create the basic JTAG communication primitive
 * on which higher layer protocols build.
 */
module JtagTap #(
    //
)(
    input  wire tck,
    input  wire trstn,
    input  wire tdi,
    input  wire tms,
    output reg  tdo
);

    wire insn_tdo;

    JtagTapFsm _fsm(
        .tck(tck),
        .trstn(trstn),
        .tms(tms)
    );

    JtagTapInsnReg _insn_reg(
        .tck(tck),
        .trstn(trstn),
        .tdi(tdi),
        .insn_tdo(insn_tdo)
    );

    JtagTapDRegs _dregs(
        .tck(tck),
        .trstn(trstn),
        .tdi(tdi),
        .tdo(tdo),
        .insn_tdo(insn_tdo)
    );


endmodule: JtagTap
