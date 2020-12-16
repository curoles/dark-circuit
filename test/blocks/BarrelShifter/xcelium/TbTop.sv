module TbTop (

);

    localparam VALUE_WIDTH = 64;
    localparam SHIFT_WIDTH = 6;

    bit  [VALUE_WIDTH-1:0] in_val;
    bit  [SHIFT_WIDTH-1:0] shift_amount;
    bit                    shift_rotate;
    bit                    left_right;
    wire [VALUE_WIDTH-1:0] out_val;

    BarrelShifter#(VALUE_WIDTH, SHIFT_WIDTH) shifter_(
        .in(in_val),
        .shift(shift_amount),
        .shift_rotate(shift_rotate),
        .left_right(left_right),
        .out(out_val)
    );

    wire clk;
    SimClkGen#(.PERIOD(1)) clk_gen_(.clk(clk));

    function bit [VALUE_WIDTH-1:0] generate_data();
        bit [VALUE_WIDTH-1:0] data;
        assert(std::randomize(data));
        return data;
    endfunction: generate_data

    initial begin: tester
        $display("BarrelShifter TB");
        repeat (1000) begin
            @(negedge clk);
            in_val = generate_data();
            shift_rotate = 0;//in_val[0];
            left_right = in_val[1];
            shift_amount = 1;//in_val[SHIFT_WIDTH-1:0];
            //$display("%h left/right:%h shift/rot:%h amount:%d",
            //    in_val, left_right, shift_rotate, shift_amount);
            @(posedge clk);
        end
        $stop;
    end: tester

    always @(posedge clk) begin: scoreboard
        bit [VALUE_WIDTH-1:0] result;
        #1;
        if (shift_rotate) begin
            if (left_right) result = in_val << shift_amount;
            else            result = in_val >> shift_amount;
        end else begin // rotate
            if (left_right) result = ({in_val, in_val} << shift_amount) >> VALUE_WIDTH;
            else            result = {in_val, in_val} >> shift_amount;
        end

        if (out_val != result)
            $error("FAILED: %h left/right:%h shift/rot:%h amount:%d out:%h vs %h",
                in_val, left_right, shift_rotate, shift_amount, out_val, result);
    end: scoreboard

endmodule: TbTop
