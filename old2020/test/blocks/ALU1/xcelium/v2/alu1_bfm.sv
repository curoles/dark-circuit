interface Alu1Bfm #(
    parameter WIDTH = 64
);

    localparam CMD_WIDTH = ALU1_CMD_WIDTH;

    typedef bit [WIDTH-1:0] IO;

    bit                  clk;
    bit  [CMD_WIDTH-1:0] alu_cmd;
    bit  [WIDTH-1:0]     alu_in1;
    bit  [WIDTH-1:0]     alu_in2;
    wire [WIDTH-1:0]     alu_out;
    wire                 alu_co;

    Alu1Op op;

    assign alu_cmd = op;

    // SimClkGen#(.PERIOD(1)) clk_gen_(.clk(clk));
    // SV does not allow module instantiation inside Interface.
    initial begin
        clk = 0;
        forever begin
            #1;
            clk = ~clk;
        end
    end

    task send_op(input IO in1, input IO in2, input Alu1Op new_op, output IO result);
        @(negedge clk);
        op = new_op;
        alu_in1 = in1;
        alu_in2 = in2;
        //$display("%-20s %h %h", op.name(), alu_in1, alu_in2);
        //do
        //    @(posedge clk);
        //while (XXX)
    endtask: send_op

endinterface: Alu1Bfm
