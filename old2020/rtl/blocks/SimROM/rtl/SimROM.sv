/* Verilog simulation ROM model.
 *
 * Author: Igor Lesik 2013-2020
 *
 * Verilog binary format example:
 * <pre>
 * @003
 * 00000011
 * 00000100
 * @005
 * 00000101
 * </pre>
 *
 * Verilog hex format example:
 * <pre>
 * @003
 * 3
 * 4
 * </pre>
 */
module SimROM #(
    parameter  DATA_SIZE  = 1, // 1-byte, 2-16bits, 4-32bits word
    localparam DATA_WIDTH = 8 * DATA_SIZE,
    parameter  ADDR_WIDTH = 8,
    parameter  MEM_SIZE   = 2**ADDR_WIDTH
)(
    input  wire                  clk,
    input  wire [ADDR_WIDTH-1:0] addr,
    output reg  [DATA_WIDTH-1:0] data
);

    reg [DATA_WIDTH-1:0] rom [MEM_SIZE];

    localparam VLOG_HEX_FORMAT = 0;
    localparam VLOG_BIN_FORMAT = 1;
    //TODO localparam SREC_FORMAT = 2;

    function int load(string filename, int format);
        if (format == VLOG_HEX_FORMAT)
            $readmemh(filename, rom);
        else if (format == VLOG_BIN_FORMAT)
            $readmemb(filename, rom);
        else
            return 0;

        return 1;
    endfunction

    always @ (posedge clk)
    begin
        //$display("ROM[%h]=%h", integer'(addr)+i, rom[integer'(addr)+i]);
        data <= rom[integer'(addr)];
    end

endmodule: SimROM

