/* Unit test of Mig2Alu: the operands (rs1, pc or 0; rs2 or the immediate) and Alu2.
 *
 * dec.alu is filled like Mig2Decode would: the operand sources and Alu2Pkg::ctrl_of of the
 * operation. The model selects the operands and computes the operation by its meaning with
 * SystemVerilog operators ($signed compares, >>> for SRA, rotates as two shifts),
 * independent of Alu2. Cases: every operation with edge values from rs1 and rs2, and from
 * rs1 and the immediate; every shift amount; every operand source; LUI (0 + imm) and AUIPC
 * (pc + imm); then random cases. Alu2's own test checks the operations exhaustively. Stops
 * at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig2Alu;
    import Mig2Pkg::*;
    import Alu2Pkg::*;

    localparam N_OPS = ALU2_ROR + 1;
    localparam SW    = $clog2(WIDTH);

    decoded_t dec;
    iaddr_t   pc;
    word_t    rs1_data;
    word_t    rs2_data;
    word_t    result;

    word_t    edges [6];
    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    word_t    rnd;
    /* verilator lint_on UNUSEDSIGNAL */
    integer   seed;

    Mig2Alu u_mig2_alu(.dec, .pc, .rs1_data, .rs2_data, .result);

    // The operation by its meaning.
    function automatic word_t op_model(input op_e op, input word_t x, input word_t y);
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

    // Apply one case and compare: operation, operand sources, rs1, rs2, imm, pc.
    task automatic check(input op_e op, input alu_a_e src_a, input logic b_imm, input word_t x,
                         input word_t y, input word_t im, input iaddr_t p);
        word_t a;
        word_t b;
        word_t exp;
        dec = '0;
        dec.imm = im;
        dec.alu = '{a: src_a, b_imm: b_imm, alu2: ctrl_of(op)};
        pc = p; rs1_data = x; rs2_data = y;
        #1;
        case (src_a)
            A_PC:    a = {p, {IADDR_START{1'b0}}};
            A_ZERO:  a = '0;
            default: a = x;
        endcase
        b   = b_imm ? im : y;
        exp = op_model(op, a, b);
        if (result !== exp)
            $fatal(1, "Mig2Alu: %s a=%0d b_imm=%b rs1=%h rs2=%h imm=%h pc=%h got %h, expected %h",
                   op.name(), src_a, b_imm, x, y, im, {p, 2'b00}, result, exp);
    endtask

    initial begin
        edges[0] = '0;
        edges[1] = word_t'(1);
        edges[2] = '1;
        edges[3] = word_t'(1) << (WIDTH - 1);
        edges[4] = ~edges[3];
        edges[5] = 32'h1234_5678;

        // Every operation: rs1 with rs2, rs1 with the immediate; every shift amount.
        for (int k = 0; k < N_OPS; k++) begin
            for (int i = 0; i < 6; i++)
                for (int j = 0; j < 6; j++) begin
                    check(op_e'(k), A_RS1, 1'b0, edges[i], edges[j], '0, '0);
                    check(op_e'(k), A_RS1, 1'b1, edges[i], '0, edges[j], '0);
                end
            for (int s = 0; s < WIDTH; s++)
                check(op_e'(k), A_RS1, 1'b1, edges[5], '0, word_t'(s), '0);
        end

        // LUI (0 + imm) and AUIPC (pc + imm).
        check(ALU2_ADD, A_ZERO, 1'b1, 32'hdead_beef, '0, 32'h1234_5000, '0);
        check(ALU2_ADD, A_ZERO, 1'b1, 32'hdead_beef, '0, 32'hffff_f000, '0);
        check(ALU2_ADD, A_PC,   1'b1, 32'hdead_beef, '0, 32'h0000_1000, 30'h0000_0040);
        check(ALU2_ADD, A_PC,   1'b1, 32'hdead_beef, '0, 32'hffff_f000, 30'h0000_0001);

        // Random: operation, operand sources and values.
        seed = 1;
        for (int i = 0; i < 5000; i++) begin
            rnd = $random(seed);
            check(op_e'(int'(rnd[4:0]) % N_OPS),
                  (rnd[6:5] == 2'd1) ? A_PC : (rnd[6:5] == 2'd2) ? A_ZERO : A_RS1, rnd[7],
                  $random(seed), $random(seed), $random(seed), iaddr_t'($random(seed)));
        end

        $display("PASS");
        $finish;
    end
endmodule
