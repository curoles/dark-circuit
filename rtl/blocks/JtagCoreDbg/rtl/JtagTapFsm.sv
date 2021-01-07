package JtagTapStatesPkg;

    // The TAP controller is/has a 16-state FSM that responds
    // to the control sequences supplied through the Test Access Port.
    localparam JTAG_TAP_NR_STATES = 16;
    localparam JTAG_TAP_STATE_VAR_WIDTH = 4; // 2^4==16

    // All test logic is disabled in this controller state enabling the normal operation of the IC.
    localparam JTAG_TAP_STATE_TEST_LOGIC_RESET = 4'hF;
    // In this controller state, the test logic in the IC is active only if certain instructions are present.
    // For example, if an instruction activates the self test, then it is executed when the controller enters this state.
    // The test logic in the IC is idle otherwise.
    localparam JTAG_TAP_STATE_RUN_TEST_IDLE    = 4'hC;
    // This controller state controls whether to enter the Data Path or the Select-IR-Scan state.
    localparam JTAG_TAP_STATE_SELECT_DR_SCAN   = 4'h7;
    // The data is parallel-loaded into the data registers selected
    // by the current instruction on the rising edge of TCK.
    localparam JTAG_TAP_STATE_CAPTURE_DR       = 4'h6;
    localparam JTAG_TAP_STATE_SHIFT_DR         = 4'h2;
    localparam JTAG_TAP_STATE_EXIT1_DR         = 4'h1;
    localparam JTAG_TAP_STATE_PAUSE_DR         = 4'h3;
    localparam JTAG_TAP_STATE_EXIT2_DR         = 4'h0;
    localparam JTAG_TAP_STATE_UPDATE_DR        = 4'h5;
    // Controls whether or not to enter the Instruction Path.
    // The Controller can return to the Test-Logic-Reset state otherwise.
    localparam JTAG_TAP_STATE_SELECT_IR_SCAN   = 4'h4;
    // The shift register bank in the Instruction Register parallel loads a pattern
    // of fixed values on the rising edge of TCK. The last two significant bits must always be "01".
    localparam JTAG_TAP_STATE_CAPTURE_IR       = 4'hE;
    // The instruction register gets connected between TDI and TDO,
    // and the captured pattern gets shifted on each rising edge of TCK.
    // The instruction available on the TDI pin is also shifted in to the instruction register. 
    localparam JTAG_TAP_STATE_SHIFT_IR         = 4'hA;
    // This controller state controls whether to enter the Pause-IR state or Update-IR state.
    localparam JTAG_TAP_STATE_EXIT1_IR         = 4'h9;
    // This state allows the shifting of the instruction register to be temporarily halted.
    localparam JTAG_TAP_STATE_PAUSE_IR         = 4'hB;
    // This controller state controls whether to enter either the Shift-IR state or Update-IR state.
    localparam JTAG_TAP_STATE_EXIT2_IR         = 4'h8;
    // The instruction in the instruction register is latched to the latch bank
    // of the Instruction Register on every falling edge of TCK.
    // This instruction becomes the current instruction once it is latched. 
    localparam JTAG_TAP_STATE_UPDATE_IR        = 4'hD;

endpackage

import JtagTapStatesPkg::*;

/* JTAG TAP state machine.
 * Author: Igor Lesik 2020
 *
 * <!-- ![TAP states](https://upload.wikimedia.org/wikipedia/commons/1/1a/JTAG_TAP_Controller_State_Diagram.svg "JTAG TAP Controller State Diagram") -->
 * ![TAP states](https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/JTAG_TAP_Controller_State_Diagram.svg/563px-JTAG_TAP_Controller_State_Diagram.svg.png)
 *
 * The state machine is simple, comprising two paths: DR path and IR path.
 * The state machine progresses on the test clock (TCK) edge,
 * with the value of the test mode select (TMS) pin controlling the behavior/transition.
 *
 * ![TAP states descr](https://www.allaboutcircuits.com/uploads/articles/jtag-part-ii-the-test-access-port-state-machine-SG-aac-image2_2.png)
 *
 * The Shift-DR and Shift-IR states are the main states for serial-loading data into
 * either data registers or the instruction register. While the state machine is in one of these states,
 * TMS is held LOW, until the shifting operation is complete.
 * The Update-DR and Update-IR states latch the data into the registers,
 * setting the data in the instruction register as the current instruction
 * (and in doing so, setting the current data register for the next cycle).
 */
module JtagTapFsm #(
    localparam WIDTH = JTAG_TAP_STATE_VAR_WIDTH
)(
    input  wire             tck,
    input  wire             trst,
    input  wire             tms,
    output reg  [WIDTH-1:0] state,

    output reg              tms_reset, // 5 consecutive TMS=1 causes reset

    output reg              state_test_logic_reset,
    output reg              state_run_test_idle,
    output reg              state_select_dr_scan,
    output reg              state_capture_dr,
    output reg              state_shift_dr,
    output reg              state_exit1_dr,
    output reg              state_pause_dr,
    output reg              state_exit2_dr,
    output reg              state_update_dr,
    output reg              state_select_ir_scan,
    output reg              state_capture_ir,
    output reg              state_shift_ir,
    output reg              state_exit1_ir,
    output reg              state_pause_ir,
    output reg              state_exit2_ir,
    output reg              state_update_ir
);
    assign state_test_logic_reset = (state == JTAG_TAP_STATE_TEST_LOGIC_RESET);
    assign state_run_test_idle    = (state == JTAG_TAP_STATE_RUN_TEST_IDLE);
    assign state_select_dr_scan   = (state == JTAG_TAP_STATE_SELECT_DR_SCAN);
    assign state_capture_dr       = (state == JTAG_TAP_STATE_CAPTURE_DR);
    assign state_shift_dr         = (state == JTAG_TAP_STATE_SHIFT_DR);
    assign state_exit1_dr         = (state == JTAG_TAP_STATE_EXIT1_DR);
    assign state_pause_dr         = (state == JTAG_TAP_STATE_PAUSE_DR);
    assign state_exit2_dr         = (state == JTAG_TAP_STATE_EXIT2_DR);
    assign state_update_dr        = (state == JTAG_TAP_STATE_UPDATE_DR);
    assign state_select_ir_scan   = (state == JTAG_TAP_STATE_SELECT_IR_SCAN);
    assign state_capture_ir       = (state == JTAG_TAP_STATE_CAPTURE_IR);
    assign state_shift_ir         = (state == JTAG_TAP_STATE_SHIFT_IR);
    assign state_exit1_ir         = (state == JTAG_TAP_STATE_EXIT1_IR);
    assign state_pause_ir         = (state == JTAG_TAP_STATE_PAUSE_IR);
    assign state_exit2_ir         = (state == JTAG_TAP_STATE_EXIT2_IR);
    assign state_update_ir        = (state == JTAG_TAP_STATE_UPDATE_IR);

    reg [WIDTH-1:0] next_state;

    // A transition between the states only occurs on the rising edge of TCK.
    always @(posedge tck) begin
        if (trst == 1 || tms_reset)
            state <= JTAG_TAP_STATE_TEST_LOGIC_RESET;
        else
            state <= next_state;
    end

    // Determination of next state
    always_comb
    begin
        case (state)
            JTAG_TAP_STATE_TEST_LOGIC_RESET: begin
                next_state = (tms)? JTAG_TAP_STATE_TEST_LOGIC_RESET:JTAG_TAP_STATE_RUN_TEST_IDLE;
                end
            JTAG_TAP_STATE_RUN_TEST_IDLE: begin
                next_state = (tms)? JTAG_TAP_STATE_SELECT_DR_SCAN:JTAG_TAP_STATE_RUN_TEST_IDLE;
                end
            JTAG_TAP_STATE_SELECT_DR_SCAN: begin
                next_state = (tms)? JTAG_TAP_STATE_SELECT_IR_SCAN:JTAG_TAP_STATE_CAPTURE_DR;
                end
            JTAG_TAP_STATE_CAPTURE_DR: begin
                next_state = (tms)? JTAG_TAP_STATE_EXIT1_DR:JTAG_TAP_STATE_SHIFT_DR;
                end
            JTAG_TAP_STATE_SHIFT_DR: begin
                next_state = (tms)? JTAG_TAP_STATE_EXIT1_DR:JTAG_TAP_STATE_SHIFT_DR;
                end
            JTAG_TAP_STATE_EXIT1_DR: begin
                next_state = (tms)? JTAG_TAP_STATE_UPDATE_DR:JTAG_TAP_STATE_PAUSE_DR;
                end
            JTAG_TAP_STATE_PAUSE_DR: begin
                next_state = (tms)? JTAG_TAP_STATE_EXIT2_DR:JTAG_TAP_STATE_PAUSE_DR;
                end
            JTAG_TAP_STATE_EXIT2_DR: begin
                next_state = (tms)? JTAG_TAP_STATE_UPDATE_DR:JTAG_TAP_STATE_SHIFT_DR;
                end
            JTAG_TAP_STATE_UPDATE_DR: begin
                next_state = (tms)? JTAG_TAP_STATE_SELECT_DR_SCAN:JTAG_TAP_STATE_RUN_TEST_IDLE;
                end
            JTAG_TAP_STATE_SELECT_IR_SCAN: begin
                next_state = (tms)? JTAG_TAP_STATE_TEST_LOGIC_RESET:JTAG_TAP_STATE_CAPTURE_IR;
                end
            JTAG_TAP_STATE_CAPTURE_IR: begin
                next_state = (tms)? JTAG_TAP_STATE_EXIT1_IR:JTAG_TAP_STATE_SHIFT_IR;
                end
            JTAG_TAP_STATE_SHIFT_IR: begin
                next_state = (tms)? JTAG_TAP_STATE_EXIT1_IR:JTAG_TAP_STATE_SHIFT_IR;
                end
            JTAG_TAP_STATE_EXIT1_IR: begin
                next_state = (tms)? JTAG_TAP_STATE_UPDATE_IR:JTAG_TAP_STATE_PAUSE_IR;
                end
            JTAG_TAP_STATE_PAUSE_IR: begin
                next_state = (tms)? JTAG_TAP_STATE_EXIT2_IR:JTAG_TAP_STATE_PAUSE_IR;
                end
            JTAG_TAP_STATE_EXIT2_IR: begin
                next_state = (tms)? JTAG_TAP_STATE_UPDATE_IR:JTAG_TAP_STATE_SHIFT_IR;
                end
            JTAG_TAP_STATE_UPDATE_IR: begin
                next_state = (tms)? JTAG_TAP_STATE_SELECT_DR_SCAN:JTAG_TAP_STATE_RUN_TEST_IDLE;
                end
            default: begin // can't actually happen
                next_state = JTAG_TAP_STATE_TEST_LOGIC_RESET;
            end
        endcase
    end

    // 5 consecutive TMS=1 causes reset
    reg tms_q1, tms_q2, tms_q3, tms_q4;
    assign tms_reset = tms & tms_q1 & tms_q2 & tms_q3 & tms_q4;

    always @(posedge tck) begin
        tms_q1 <= tms;
        tms_q2 <= tms_q1;
        tms_q3 <= tms_q2;
        tms_q4 <= tms_q3;
    end

endmodule

