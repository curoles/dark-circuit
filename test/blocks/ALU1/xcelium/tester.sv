module Tester #(
    parameter WIDTH = 64
)(
    Alu1Bfm bfm
);

    localparam CMD_WIDTH = ALU1_CMD_WIDTH;

    function bit [CMD_WIDTH-1:0] generate_op();
        generate_op = $urandom % ALU1_NR_COMMANDS;
    endfunction

    function bit [WIDTH-1:0] generate_data();
        bit [2:0] zero_ones;
        zero_ones = $urandom;
        if (zero_ones == 3'b000)
            return {WIDTH{1'b0}};
        else if (zero_ones == 3'b111)
            return {WIDTH{1'b1}};
        else
            return (($urandom << WIDTH/2) | $urandom);
    endfunction: generate_data

    initial begin: tester
        bit  [CMD_WIDTH-1:0] cmd;
        bit  [WIDTH-1:0]     in1;
        bit  [WIDTH-1:0]     in2;
        bit  [WIDTH-1:0]     result;

        $display("Testing...");
        repeat (1000) begin
            cmd = generate_op();
            in1 = generate_data();
            in2 = generate_data();
            bfm.send_op(in1, in2, Alu1Op'(cmd), result);
        end
        $stop;
    end: tester

endmodule: Tester
