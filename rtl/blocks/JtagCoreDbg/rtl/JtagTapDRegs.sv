// version:part number:manufacturer id:1 required by standard
localparam DEFAULT_IDCODE_VALUE = 32'b0001_0100100101010001_00011100001_1;

/* JTAG TAP Data Registers and TDO MUX.
 *
 * Author: Igor Lesik 2020
 *
 */
module JtagTapDRegs #(
    parameter IDCODE_VALUE=DEFAULT_IDCODE_VALUE,
    parameter INSN_WIDTH=8
)(
    input  wire                  tck,
    input  wire                  trst,
    input  wire                  tdi,
    input  wire                  state_test_logic_reset,
    input  wire                  state_capture_dr,
    input  wire                  state_shift_dr,
    input  wire                  state_shift_ir,
    input  wire [INSN_WIDTH-1:0] latched_jtag_ir,
    // TDI signals from other modules Data Registers
    input  wire                  debug_tdo,
    input  wire                  bs_chain_tdo,
    input  wire                  mbist_tdo,
    input  wire                  insn_tdo,
    input  wire                  jdpacc_tdo,
    input  wire                  cdpacc_tdo,

    output reg                   tdo,
    // 1-bit telling instruction type
    output reg                   insn_extest_select,
    output reg                   insn_sample_preload_select,
    output reg                   insn_idcode_select,
    output reg                   insn_mbist_select,
    output reg                   insn_debug_select,
    output reg                   insn_bypass_select,
    output reg                   insn_jdpacc_select,
    output reg                   insn_cdpacc_select
);
    localparam INSN_EXTEST         = 8'b0000_0000;
    localparam INSN_SAMPLE_PRELOAD = 8'b0000_0001;
    localparam INSN_IDCODE         = 8'b0000_0010;
    localparam INSN_DEBUG          = 8'b0000_1000;
    localparam INSN_MBIST          = 8'b0000_1001;
    localparam INSN_JDPACC         = 8'b0000_0100;
    localparam INSN_CDPACC         = 8'b0000_0101;
    localparam INSN_BYPASS         = 8'b1111_1111; // all 1's required by the standard

    wire idcode_tdo, bypass_tdo;

    assign insn_extest_select           = (latched_jtag_ir == INSN_EXTEST);
    assign insn_sample_preload_select   = (latched_jtag_ir == INSN_SAMPLE_PRELOAD);
    assign insn_idcode_select           = (latched_jtag_ir == INSN_IDCODE);
    assign insn_mbist_select            = (latched_jtag_ir == INSN_MBIST);
    assign insn_debug_select            = (latched_jtag_ir == INSN_DEBUG);
    assign insn_bypass_select           = (latched_jtag_ir == INSN_BYPASS);
    assign insn_jdpacc_select           = (latched_jtag_ir == INSN_JDPACC);
    assign insn_cdpacc_select           = (latched_jtag_ir == INSN_CDPACC);

    // TDO is muxed/selected based on value of Instruction Register (IR).
    reg tdo_mux;

    // TDO changes state at negative edge of TCK
    always @(negedge tck) begin
        tdo = tdo_mux;
    end

    // MUX-ing TDOs of the Data Registers
    always_comb begin
        if (state_shift_ir)
            tdo_mux = insn_tdo;
        else begin
            case (latched_jtag_ir)
                INSN_IDCODE:         tdo_mux = idcode_tdo;
                INSN_DEBUG:          tdo_mux = debug_tdo;
                INSN_SAMPLE_PRELOAD: tdo_mux = bs_chain_tdo;
                INSN_EXTEST:         tdo_mux = bs_chain_tdo;
                INSN_MBIST:          tdo_mux = mbist_tdo;
                INSN_JDPACC:         tdo_mux = jdpacc_tdo;
                INSN_CDPACC:         tdo_mux = cdpacc_tdo;
                INSN_BYPASS:         tdo_mux = bypass_tdo;
                default:             tdo_mux = bypass_tdo;
            endcase
        end
    end

    // IDCODE Data Register
    reg [31:0] idcode_reg;

    always @(posedge tck)
    begin
        if (trst == 1)
            idcode_reg <= IDCODE_VALUE; // IDCODE selected after reset
        else if (state_test_logic_reset)
            idcode_reg <= IDCODE_VALUE; // IDCODE selected after reset
        else if (insn_idcode_select & state_capture_dr)
            idcode_reg <= IDCODE_VALUE;
        else if (insn_idcode_select & state_shift_dr) begin
            idcode_reg <= {tdi, idcode_reg[31:1]};
            //$display("JTAG TAP IDCODE Shift-DR %h", idcode_reg);
        end
    end

    assign idcode_tdo = idcode_reg[0];

    // BYPASS Data Register
    reg bypass_reg; // 1-bit register

    always @(posedge tck)
    begin
        if (trst == 1)
            bypass_reg <= 1'b0;
        else if (state_test_logic_reset == 1)
            bypass_reg <= 1'b0;
        else if (insn_bypass_select & state_capture_dr)
            bypass_reg <= 1'b0;
        else if (insn_bypass_select & state_shift_dr)
            bypass_reg <= tdi;
    end

    assign bypass_tdo = bypass_reg;


endmodule
