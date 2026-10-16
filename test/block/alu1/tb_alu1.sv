/* Test of Alu1 block, behave or struct version.
 *
 * WIDTH=4: exhaustive, every cmd (also 12..15) x in1 x in2.
 * WIDTH=64: random, inputs are often all zeros or all ones.
 * Model uses meaning of every command, not the adder: co of SUB is in1 >= in2,
 * co of DEC is in1 != 0, co of TRANSFER2 is 1, co of logic is 0, ...
 * Stops at the first mismatch with $fatal.
 */
module TbAlu1;
    import Alu1Pkg::*;

    reg  [3:0]  cmd4;
    reg  [3:0]  a4;
    reg  [3:0]  b4;
    wire [3:0]  out4;
    wire        co4;
    reg  [3:0]  cmd64;
    reg  [63:0] a64;
    reg  [63:0] b64;
    wire [63:0] out64;
    wire        co64;
    // Model result: bit 64 is co, low WIDTH bits are out.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [64:0] exp4;
    /* verilator lint_on UNUSEDSIGNAL */
    reg  [64:0] exp64;
    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [31:0] rnd;
    /* verilator lint_on UNUSEDSIGNAL */
    integer i;
    integer seed;

    Alu1 #(.WIDTH(4))  u_alu1_4 (.cmd(cmd4),  .in1(a4),  .in2(b4),  .co(co4),  .out(out4));
    Alu1 #(.WIDTH(64)) u_alu1_64(.cmd(cmd64), .in1(a64), .in2(b64), .co(co64), .out(out64));

    // Expected {co, out} for WIDTH w, operands in the low w bits.
    function automatic [64:0] model(input integer w, input [3:0] c, input [63:0] a, input [63:0] b);
        reg [63:0] mask;
        reg [64:0] sum;
        reg [3:0]  op;
        reg [63:0] r;
        reg        carry;
        begin
            mask = (w == 64) ? {64{1'b1}} : (64'd1 << w) - 64'd1;
            op = (c >= 12) ? c - 4'd4 : c;  // 12..15 work as 8..11
            sum = 0;
            r = 0;
            carry = 0;
            case (op)
                OP_TRANSFER:   begin r = a;         carry = 0;                            end
                OP_INC:        begin r = a + 1;     carry = (a == mask);                  end
                OP_ADD:        begin sum = {1'b0, a} + {1'b0, b};
                                     r = sum[63:0]; carry = (sum > {1'b0, mask});         end
                OP_ADD_PLUS1:  begin sum = {1'b0, a} + {1'b0, b} + 65'd1;
                                     r = sum[63:0]; carry = (sum > {1'b0, mask});         end
                OP_SUB_MINUS1: begin r = a - b - 1; carry = (a > b);                      end
                OP_SUB:        begin r = a - b;     carry = (a >= b);                     end
                OP_DEC:        begin r = a - 1;     carry = (a != 0);                     end
                OP_TRANSFER2:  begin r = a;         carry = 1;                            end
                OP_AND:        begin r = a & b;     carry = 0;                            end
                OP_OR:         begin r = a | b;     carry = 0;                            end
                OP_XOR:        begin r = a ^ b;     carry = 0;                            end
                default:       begin r = ~a;        carry = 0;                            end  // OP_NOT
            endcase
            model = {carry, r & mask};
        end
    endfunction

    // Random operand: all zeros or all ones in 1 of 4 cases each.
    function automatic [63:0] operand(input [31:0] r1, input [31:0] r2);
        begin
            case (r1[1:0])
                2'b00:   operand = 64'd0;
                2'b11:   operand = {64{1'b1}};
                default: operand = {r1, r2};
            endcase
        end
    endfunction

    initial begin
        // WIDTH=4, exhaustive.
        cmd64 = 0; a64 = 0; b64 = 0;
        for (i = 0; i < (1 << 12); i = i + 1) begin
            {cmd4, a4, b4} = i[11:0];
            #1;
            exp4 = model(4, cmd4, {60'd0, a4}, {60'd0, b4});
            if (out4 !== exp4[3:0] || co4 !== exp4[64])
                $fatal(1, "Alu1 4: cmd=%0d in1=%h in2=%h got co=%b out=%h, expected co=%b out=%h",
                       cmd4, a4, b4, co4, out4, exp4[64], exp4[3:0]);
        end

        // WIDTH=64, random; few cycles, struct of 64 bits is slow in Icarus.
        seed = 1;
        for (i = 0; i < 2000; i = i + 1) begin
            rnd   = $random(seed);
            cmd64 = rnd[3:0];
            a64   = operand($random(seed), $random(seed));
            b64   = operand($random(seed), $random(seed));
            #1;
            exp64 = model(64, cmd64, a64, b64);
            if (out64 !== exp64[63:0] || co64 !== exp64[64])
                $fatal(1, "Alu1 64: cmd=%0d in1=%h in2=%h got co=%b out=%h, expected co=%b out=%h",
                       cmd64, a64, b64, co64, out64, exp64[64], exp64[63:0]);
        end

        $display("PASS");
        $finish;
    end
endmodule
