/* JTAG device TAP.
 *
 * Author: Igor Lesik 2020
 *
 * In JTAG, devices expose one or more test access ports (TAPs).
 * A daisy chain of TAPs is called a scan chain.
 *
 * ![scan chain](https://upload.wikimedia.org/wikipedia/commons/c/c9/Jtag_chain.svg "Scan chain")
 *
 * The TAP connector pins are:
 *
 * - TDI: Test Data In
 * - TDO: Test Data Out
 * - TCK: Test Clock
 * - TMS: Test Mode Select
 * - TRST: Test Reset (optional)
 *
 * To use JTAG, a host is connected to the target's JTAG signals (TMS, TCK, TDI, TDO, etc.)
 * through some kind of JTAG adapter, which may need to handle issues like level shifting
 * and galvanic isolation.
 * The adapter connects to the host using some interface such as USB, PCI, Ethernet, and so forth.
 *
 * The host communicates with the TAPs by manipulating TMS and TDI in conjunction with TCK,
 * and reading results through TDO.
 *
 * TMS/TDI/TCK transitions create the basic JTAG communication primitive
 * on which higher layer protocols build.
 *
 * The test access point (TAP) is composed of:
 *
 * - the TAP controller,
 * - an instruction register,
 * - and several test data registers,
 * - in addition to some glue-logic.
 *
 * The TAP controller contains the testing state machine, and is responsible
 * for interpreting the TCK and TMS signals.
 *
 * The data input pin is used for loading data into the boundary cells
 * between physical pins and the IC core, and loading data into the instruction
 * register or one of the data registers.
 *
 * The data output pin is used to read data from the boundary cells,
 * or to read data from the instruction or data registers.
 *
 * References:
 *
 * - [IEEE 1149.1-1990 - IEEE Standard Test Access Port and Boundary-Scan Architecture](
 *   https://standards.ieee.org/standard/1149_1-1990.html)
 * - [Timeline of JTAG-related standards](
 *   https://www.corelis.com/wp-content/uploads/2017/05/timeline_72dpi1.png)
 * - [JTAG connectors and interfaces](
 *   https://www.allaboutcircuits.com/technical-articles/jtag-connectors-and-interfaces/)
 * - [practical example of JTAG interface programming with Black Magic Probe](
 *   https://github.com/blacksphere/blackmagic)
 * - [JTAG Primer from TI](https://www.ti.com/lit/an/ssya002c/ssya002c.pdf)
 * - [Boundary-scan test example](
 *   https://www.corelis.com/education/tutorials/jtag-tutorial/what-is-jtag/)
 * - [Adding User Specific Registers to JTAG](
 *   https://www.embecosm.com/appnotes/ean5/html/ch02s01s02.html)
 */
module JtagTap #(
    localparam INSN_WIDTH=8,
    localparam STATE_WIDTH=4
)(
    input  wire tck,   // test clock
    input  wire trst,  // test reset
    input  wire tdi,   // test Data In
    input  wire tms,   // test Mode Select
    output reg  tdo,   // test Data Out

    input wire jdpacc_tdo,
    input wire cdpacc_tdo
);

    wire insn_tdo; // TAP InsnReg TDO wire
    wire debug_tdo;
    wire bs_chain_tdo;
    wire mbist_tdo;

    wire state_test_logic_reset;
    wire state_capture_dr;
    wire state_capture_ir;
    wire state_shift_dr;
    wire state_shift_ir;
    wire state_update_ir;
    wire state_pause_ir;
    wire state_pause_dr;
    wire state_exit1_ir, state_exit2_ir;
    wire state_exit1_dr, state_exit2_dr;
    wire state_run_test_idle, state_select_dr_scan;

    wire insn_extest_select;
    wire insn_sample_preload_select;
    wire insn_idcode_select;
    wire insn_mbist_select;
    wire insn_debug_select;
    wire insn_bypass_select;
    wire insn_jdpacc_select;
    wire insn_cdpacc_select;

    wire [INSN_WIDTH-1:0] latched_jtag_ir;
    wire [STATE_WIDTH-1:0] state;

    JtagTapFsm _fsm(
        .tck(tck),
        .trst(trst),
        .tms(tms),
        .state(state),
        .tms_reset(tms_reset), // 5 consecutive TMS=1 causes reset
        .state_test_logic_reset(state_test_logic_reset),
        .state_run_test_idle(state_run_test_idle),
        .state_select_dr_scan(state_select_dr_scan),
        .state_capture_dr(state_capture_dr),
        .state_shift_dr(state_shift_dr),
        .state_exit1_dr(state_exit1_dr),
        .state_pause_dr(state_pause_dr),
        .state_exit2_dr(state_exit2_dr),
        .state_update_dr(state_update_dr),
        .state_select_ir_scan(state_select_ir_scan),
        .state_capture_ir(state_capture_ir),
        .state_shift_ir(state_shift_ir),
        .state_exit1_ir(state_exit1_ir),
        .state_pause_ir(state_pause_ir),
        .state_exit2_ir(state_exit2_ir),
        .state_update_ir(state_update_ir)
    );

    JtagTapInsnReg _insn_reg(
        .tck(tck),
        .trst(trst),
        .tdi(tdi),
        .insn_tdo(insn_tdo),
        .state_test_logic_reset(state_test_logic_reset),
        .state_capture_ir(state_capture_ir),
        .state_shift_ir(state_shift_ir),
        .state_update_ir(state_update_ir)
    );

    JtagTapDRegs _dregs(
        .tck(tck),
        .trst(trst),
        .tdi(tdi),
        .tdo(tdo),
        .state_test_logic_reset(state_test_logic_reset),
        .state_capture_dr(state_capture_dr),
        .state_shift_dr(state_shift_dr),
        .state_shift_ir(state_shift_ir),
        .latched_jtag_ir(latched_jtag_ir),
        .debug_tdo(debug_tdo),
        .bs_chain_tdo(debug_tdo),
        .mbist_tdo(mbist_tdo),
        .insn_tdo(insn_tdo),
        .jdpacc_tdo(jdpacc_tdo),
        .cdpacc_tdo(cdpacc_tdo),
        .insn_extest_select(insn_extest_select),
        .insn_sample_preload_select(insn_sample_preload_select),
        .insn_idcode_select(insn_idcode_select),
        .insn_mbist_select(insn_mbist_select),
        .insn_debug_select(insn_debug_select),
        .insn_bypass_select(insn_bypass_select),
        .insn_jdpacc_select(insn_jdpacc_select),
        .insn_cdpacc_select(insn_cdpacc_select)
    );


endmodule: JtagTap
