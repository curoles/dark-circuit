/* Test of Alu2, behave or struct version.
 *
 * Every operation gets its controls from Alu2Pkg::ctrl_of, so the test checks the package
 * and the block together. The model computes each operation by its meaning, with the
 * simulator's operators ($signed compares, >>> for SRA, rotates as two shifts). WIDTH 4:
 * exhaustive, every operation x a x b. WIDTH 32 and, on Verilator, 64: every operation with
 * edge operands (0, 1, all ones, the sign bit alone, the largest positive, every shift
 * amount) and random ones: 5000 on Verilator, 300 on Icarus. Stops at the first mismatch
 * with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbAlu2Check import Alu2Pkg::*; #(
    parameter WIDTH = 32
)(
    output logic done
);
`ifdef VERILATOR
    localparam N_RANDOM = 5000;
`else
    localparam N_RANDOM = 300;
`endif
    localparam SW         = $clog2(WIDTH);
    localparam N_OPS      = ALU2_ROR + 1;
    localparam EXHAUSTIVE = WIDTH <= 4;

    typedef logic [WIDTH-1:0] word_t;
    localparam word_t ONES = '1;
    localparam word_t SIGN = word_t'(1) << (WIDTH - 1);

    ctrl_t ctrl;
    word_t a;
    word_t b;
    wire   [WIDTH-1:0] out;
    integer seed;

    Alu2 #(.WIDTH(WIDTH)) u_alu2(.ctrl, .a, .b, .out);

    // The operation by its meaning.
    function automatic word_t model(input op_e op, input word_t x, input word_t y);
        int sh;
        sh = int'(y[SW-1:0]);
        case (op)
            ALU2_ADD:  return x + y;
            ALU2_SUB:  return x - y;
            ALU2_AND:  return x & y;
            ALU2_OR:   return x | y;
            ALU2_XOR:  return x ^ y;
            ALU2_ANDN: return x & ~y;
            ALU2_ORN:  return x | ~y;
            ALU2_XNOR: return ~(x ^ y);
            ALU2_SLT:  return word_t'($signed(x) < $signed(y));
            ALU2_SLTU: return word_t'(x < y);
            ALU2_MIN:  return ($signed(x) < $signed(y)) ? x : y;
            ALU2_MINU: return (x < y) ? x : y;
            ALU2_MAX:  return ($signed(x) < $signed(y)) ? y : x;
            ALU2_MAXU: return (x < y) ? y : x;
            ALU2_SLL:  return x << sh;
            ALU2_SRL:  return x >> sh;
            ALU2_SRA:  return word_t'($signed(x) >>> sh);
            ALU2_ROL:  return (x << sh) | (x >> (WIDTH - sh));
            ALU2_ROR:  return (x >> sh) | (x << (WIDTH - sh));
            default:   return 'x;   // not an operation: never asked
        endcase
    endfunction

    task automatic check(input op_e op, input word_t x, input word_t y);
        word_t exp;
        ctrl = ctrl_of(op);
        a = x;
        b = y;
        #1;
        exp = model(op, x, y);
        if (out !== exp)
            $fatal(1, "Alu2 %0d: %s a=%h b=%h got %h, expected %h", WIDTH, op.name(), x, y, out, exp);
    endtask

    // A random word: 16 random bits at a time.
    function automatic word_t random_word();
        word_t x;
        x = '0;
        for (int i = 0; i < WIDTH; i += 16)
            x = word_t'({x, 16'($random(seed))});
        return x;
    endfunction

    word_t edges [6];

    initial begin
        done = 1'b0;
        seed = WIDTH;
        edges[0] = '0;
        edges[1] = word_t'(1);
        edges[2] = ONES;
        edges[3] = SIGN;
        edges[4] = ~SIGN;
        edges[5] = SIGN | word_t'(1);
        for (int k = 0; k < N_OPS; k++)
            if (EXHAUSTIVE) begin
                for (int i = 0; i < (1 << WIDTH); i++)
                    for (int j = 0; j < (1 << WIDTH); j++)
                        check(op_e'(k), word_t'(i), word_t'(j));
            end else begin
                for (int i = 0; i < 6; i++)
                    for (int j = 0; j < 6; j++)
                        check(op_e'(k), edges[i], edges[j]);
                for (int s = 0; s < WIDTH; s++)             // every shift amount
                    check(op_e'(k), edges[5] | (edges[1] << (WIDTH / 2)), word_t'(s));
                for (int i = 0; i < N_RANDOM; i++)
                    check(op_e'(k), random_word(), random_word());
            end
        done = 1'b1;
    end
endmodule

module TbAlu2;
    wire done4;
    wire done32;
    wire done64;

    TbAlu2Check #(.WIDTH(4))  u_check_4 (.done(done4));
    TbAlu2Check #(.WIDTH(32)) u_check_32(.done(done32));
`ifdef VERILATOR
    TbAlu2Check #(.WIDTH(64)) u_check_64(.done(done64));
`else
    assign done64 = 1'b1;   // Icarus: the time (about 1 s at most for a library test)
`endif

    initial begin
        wait (done4 && done32 && done64);
        $finish;
    end
endmodule
