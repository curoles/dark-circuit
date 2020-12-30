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
 */
module JtagTap #(
    localparam INSN_WIDTH=4,
    localparam STATE_WIDTH=4
)(
    input  wire tck,   // test clock
    input  wire trstn, // test reset
    input  wire tdi,   // test Data In
    input  wire tms,   // test Mode Select
    output reg  tdo    // test Data Out
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

    wire [INSN_WIDTH-1:0] latched_jtag_ir;
    wire [STATE_WIDTH-1:0] state;

    JtagTapFsm _fsm(
        .tck(tck),
        .trstn(trstn),
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
        .trstn(trstn),
        .tdi(tdi),
        .insn_tdo(insn_tdo),
        .state_test_logic_reset(state_test_logic_reset),
        .state_capture_ir(state_capture_ir),
        .state_shift_ir(state_shift_ir),
        .state_update_ir(state_update_ir)
    );

    JtagTapDRegs _dregs(
        .tck(tck),
        .trstn(trstn),
        .tdi(tdi),
        .tdo(tdo),
        .state_test_logic_reset(state_test_logic_reset),
        .state_capture_dr(state_capture_dr),
        .state_shift_dr(state_shift_dr),
        .state_shift_ir(state_shift_ir),
        .debug_tdo(debug_tdo),
        .bs_chain_tdo(debug_tdo),
        .mbist_tdo(mbist_tdo),
        .insn_tdo(insn_tdo),
        .insn_extest_select(insn_extest_select),
        .insn_sample_preload_select(insn_sample_preload_select),
        .insn_idcode_select(insn_idcode_select),
        .insn_mbist_select(insn_mbist_select),
        .insn_debug_select(insn_debug_select),
        .insn_bypass_select(insn_bypass_select)
    );


endmodule: JtagTap
