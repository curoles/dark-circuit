module TbTop (

);

    localparam WIDTH = 64;
    localparam CMD_WIDTH = ALU1_CMD_WIDTH;

    wire                 clk;
    bit  [CMD_WIDTH-1:0] alu_cmd;
    bit  [WIDTH-1:0]     alu_in1;
    bit  [WIDTH-1:0]     alu_in2;
    wire [WIDTH-1:0]     alu_out;
    wire                 alu_co;

    Alu1#(.WIDTH(WIDTH))
        alu_(.cmd(alu_cmd), .in1(alu_in1), .in2(alu_in2), .co(alu_co), .out(alu_out));

    SimClkGen#(.PERIOD(1)) clk_gen_(.clk(clk));

    function bit [CMD_WIDTH-1:0] generate_op();
        generate_op = $urandom % ALU1_NR_COMMANDS;
    endfunction

    function bit [WIDTH-1:0] generate_data();
        bit [1:0] zero_ones;
        zero_ones = $random;
        if (zero_ones == 2'b00)
            return {WIDTH{1'b0}};
        else if (zero_ones == 2'b11)
            return {WIDTH{1'b1}};
        else
            return $random;
    endfunction: generate_data

    initial begin: tester
        $display("ALU1 TB");
        repeat (1000) begin
            @(negedge clk);
            alu_cmd = generate_op();
            alu_in1 = generate_data();
            alu_in2 = generate_data();
            //$display("%d %h %h", alu_cmd, alu_in1, alu_in2);
            @(posedge clk);
        end
        $stop;
    end: tester

    always @(posedge clk) begin: scoreboard
        bit [WIDTH-1:0] result;
        #1;
        case (alu_cmd)
        ALU1_OP_TRANSFER:   result = alu_in1;
        ALU1_OP_INC:        result = alu_in1 + 1;
        ALU1_OP_ADD:        result = alu_in1 + alu_in2;
        ALU1_OP_ADD_PLUS1:  result = alu_in1 + alu_in2 + 1;
        ALU1_OP_SUB_MINUS1: result = alu_in1 - alu_in2 - 1;
        ALU1_OP_SUB:        result = alu_in1 - alu_in2;
        ALU1_OP_DEC:        result = alu_in1 - 1;
        ALU1_OP_TRANSFER2:  result = alu_in1;
        ALU1_OP_AND:        result = alu_in1 & alu_in2;
        ALU1_OP_OR:         result = alu_in1 | alu_in2;
        ALU1_OP_XOR:        result = alu_in1 ^ alu_in2;
        ALU1_OP_NOT:        result = ~alu_in1;
        endcase

        if (alu_out != result)
            $error("FAILED: in1: %0h  in2: %0h  op: %d result: %0h vs %0h",
                alu_in1, alu_in2, alu_cmd, alu_out, result);
    end: scoreboard

endmodule: TbTop
