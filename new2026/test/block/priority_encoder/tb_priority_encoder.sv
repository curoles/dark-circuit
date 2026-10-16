/* Test of PriorityEncoder block, behave or struct version.
 *
 * 1. SIZE 1, 3 and 4 side by side:
 *    all 8-bit inputs (all inputs of SIZE 1 and 3),
 *    then 16-bit inputs with one and two bits set and random 16-bit inputs.
 * 2. Decoder then PriorityEncoder, SIZE 3: encoder gives back decoder input.
 *
 * Stops at the first mismatch with $fatal.
 */
module TbPriorityEncoder;
    reg  [15:0] v;
    wire [0:0]  out1;
    wire [2:0]  out3;
    wire [3:0]  out4;
    wire        valid1;
    wire        valid3;
    wire        valid4;
    reg  [3:0]  exp1;
    reg  [3:0]  exp3;
    reg  [3:0]  exp4;
    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [31:0] r;
    /* verilator lint_on UNUSEDSIGNAL */
    integer i;
    integer k1;
    integer k2;
    integer seed;

    // Decoder then PriorityEncoder.
    reg  [2:0]  dec_in;
    reg         dec_en;
    wire [7:0]  dec_out;
    wire [2:0]  rt_out;
    wire        rt_valid;

    PriorityEncoder #(.SIZE(1)) u_priority_encoder_1(.in(v[1:0]), .out(out1), .valid(valid1));
    PriorityEncoder #(.SIZE(3)) u_priority_encoder_3(.in(v[7:0]), .out(out3), .valid(valid3));
    PriorityEncoder #(.SIZE(4)) u_priority_encoder_4(.in(v),      .out(out4), .valid(valid4));

    Decoder         #(.SIZE(3)) u_decoder(.in(dec_in), .en(dec_en), .out(dec_out));
    PriorityEncoder #(.SIZE(3)) u_priority_encoder_rt(.in(dec_out), .out(rt_out), .valid(rt_valid));

    // Index of the highest bit set in x[width-1:0], 0 if none.
    function automatic [3:0] top_index(input [15:0] x, input integer width);
        integer k;
        begin
            top_index = 4'd0;
            for (k = 0; k < width; k = k + 1)
                if (x[k])
                    top_index = k[3:0];
        end
    endfunction

    // Apply input to all 3 encoders and check them.
    task check(input [15:0] x);
        begin
            v = x;
            #1;
            exp1 = top_index(v, 2);
            exp3 = top_index(v, 8);
            exp4 = top_index(v, 16);
            if ({3'b000, out1} !== exp1 || valid1 !== |v[1:0])
                $fatal(1, "PriorityEncoder SIZE=1: in=%b got out=%b valid=%b", v[1:0], out1, valid1);
            if ({1'b0, out3} !== exp3 || valid3 !== |v[7:0])
                $fatal(1, "PriorityEncoder SIZE=3: in=%b got out=%0d valid=%b, expected out=%0d", v[7:0], out3, valid3, exp3);
            if (out4 !== exp4 || valid4 !== |v)
                $fatal(1, "PriorityEncoder SIZE=4: in=%b got out=%0d valid=%b, expected out=%0d", v, out4, valid4, exp4);
        end
    endtask

    initial begin
        dec_in = 0; dec_en = 0;

        // 1. All 8-bit inputs: all inputs of SIZE 1 and 3.
        for (i = 0; i < 2**8; i = i + 1)
            check({8'b0, i[7:0]});
        // 16-bit inputs with one bit set and with two bits set: every pair of bits.
        for (k1 = 0; k1 < 16; k1 = k1 + 1) begin
            check(16'd1 << k1);
            for (k2 = k1 + 1; k2 < 16; k2 = k2 + 1)
                check((16'd1 << k1) | (16'd1 << k2));
        end
        // Random 16-bit inputs.
        seed = 1;
        for (i = 0; i < 2000; i = i + 1) begin
            r = $random(seed);
            check(r[15:0]);
        end

        // 2. Decoder then PriorityEncoder gives back decoder input when enabled.
        for (i = 0; i < 2**4; i = i + 1) begin
            {dec_en, dec_in} = i[3:0];
            #1;
            if (dec_en && (rt_out !== dec_in || rt_valid !== 1'b1))
                $fatal(1, "Decoder+PriorityEncoder: in=%0d got out=%0d valid=%b", dec_in, rt_out, rt_valid);
            if (!dec_en && (rt_out !== 3'd0 || rt_valid !== 1'b0))
                $fatal(1, "Decoder+PriorityEncoder: en=0 got out=%0d valid=%b, expected 0 0", rt_out, rt_valid);
        end

        $display("PASS");
        $finish;
    end
endmodule
