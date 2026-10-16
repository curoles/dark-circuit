interface CounterBfm #(
    parameter WIDTH = 8
);

    typedef bit [WIDTH-1:0] IO;

    bit              clk;
    bit              rst;
    bit  [WIDTH-1:0] in_val;
    bit              load;
    bit              up_down;
    bit              count_en;
    wire [WIDTH-1:0] out_val;
    wire             carry_out;

    longint unsigned clk_cnt;
    longint unsigned cnt;

    initial begin
        rst = 0;
        clk_cnt = 0;
        cnt = 0;
        count_en = 0;
        clk = 0;
        forever begin
            #1;
            clk = ~clk;
            clk_cnt = clk_cnt + 1;
            if (clk && count_en) cnt = cnt + ((up_down)? 1:-1);
        end
    end

    task send_reset();
        rst = 1;
        repeat(2) @(posedge clk);
        rst = 0;
        cnt = 0;
    endtask: send_reset

    task send_load(input IO load_val);
        @(posedge clk);
        load = 1;
        in_val = load_val;
        @(posedge clk);
        load = 0;
        cnt = load_val;
    endtask: send_load

endinterface: CounterBfm
