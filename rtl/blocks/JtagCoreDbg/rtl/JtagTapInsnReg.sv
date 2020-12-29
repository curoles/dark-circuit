/* JTAG TAP Instruction Register.
 * Author: Igor Lesik 2020
 *
 *
 */
module JtagTapInsnReg #(
    parameter WIDTH=4,
    parameter INSN_IDCODE=4'b0010
)(
    input  wire tck,
    input  wire trstn,
    input  wire tdi,
    input  wire state_test_logic_reset,
    input  wire state_capture_ir,
    input  wire state_shift_ir,
    input  wire state_update_ir,
    output reg  insn_tdo
);

    reg [WIDTH-1:0]  jtag_ir;         // Instruction register
    reg [WIDTH-1:0]  latched_jtag_ir; // Insn Reg latched on negedge of TCK

    always @(posedge tck) begin
        if (trstn == 0)
            jtag_ir <= {WIDTH{1'b0}};
        else if (state_test_logic_reset == 1)
	        jtag_ir <= {WIDTH{1'b0}};
        else if (state_capture_ir)
            jtag_ir <= 4'b0101; // This value is fixed for easier fault detection; TODO ???
        else if (state_shift_ir)
            jtag_ir <= {tdi, jtag_ir[WIDTH-1:1]};
    end

    assign insn_tdo = jtag_ir[0];

    always @(negedge tck) begin
        if (trstn == 0)
            latched_jtag_ir <= INSN_IDCODE;
        else if (state_test_logic_reset)
            latched_jtag_ir <= INSN_IDCODE;
        else if (state_update_ir)
            latched_jtag_ir <= jtag_ir;
    end

endmodule

