/* Unit test of Mig2Alu.
 *
 * The model computes RV32I results with SystemVerilog operators (+, -, signed and
 * unsigned <, <<, >>, >>>), independent of Alu1 and BarrelShifter. dec is filled
 * directly, like Mig2Decode would: for OP-IMM alt is imm[10], shifts have funct7 in
 * imm[11:5]. Cases: every OP and OP-IMM operation with edge values, LUI, AUIPC,
 * then random cases. OP with alt: SUB, SRA, and the Zbb ANDN, ORN, XNOR (funct3 of AND, OR,
 * XOR); OP with minmax: the Zbb MIN, MINU, MAX, MAXU (funct3 100..111). Stops at the first
 * mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig2Alu;
    import Mig2Pkg::*;
    import RiscvPkg::*;

    decoded_t dec;
    iaddr_t   pc;
    word_t    rs1_data;
    word_t    rs2_data;
    word_t    result;

    word_t    edges [6];
    word_t    rnd;
    funct3_t  rnd_f3;       // funct3 of a random case
    integer   i;
    integer   j;
    integer   f;
    integer   seed;

    Mig2Alu u_mig2_alu(.dec, .pc, .rs1_data, .rs2_data, .result);

    // Expected result; mm: MIN, MINU, MAX, MAXU by funct3.
    function automatic word_t model(input kind_e k, input funct3_t f3, input logic al,
                                    input logic mm, input word_t x, input word_t y,
                                    input word_t im, input word_t pcb);
        word_t bb;
        if (k == KIND_LUI)   return im;
        if (k == KIND_AUIPC) return pcb + im;
        if (mm)
            case (f3)
                3'b100:  return ($signed(x) < $signed(y)) ? x : y;     // MIN
                3'b101:  return (x < y) ? x : y;                       // MINU
                3'b110:  return ($signed(x) < $signed(y)) ? y : x;     // MAX
                default: return (x < y) ? y : x;                       // MAXU
            endcase
        bb = (k == KIND_OP) ? y : im;
        case (f3)
            F3_ADD_SUB: return (k == KIND_OP && al) ? x - bb : x + bb;
            F3_SLL:     return x << bb[4:0];
            F3_SLT:     return ($signed(x) < $signed(bb)) ? 32'd1 : 32'd0;
            F3_SLTU:    return (x < bb) ? 32'd1 : 32'd0;
            F3_XOR:     return (k == KIND_OP && al) ? ~(x ^ bb) : x ^ bb;    // XNOR
            // Not `al ? $signed(x) >>> s : x >> s`: a ?: with an unsigned branch makes
            // the whole expression unsigned, then >>> shifts in zeros.
            F3_SRL_SRA: if (al) return $signed(x) >>> bb[4:0];
                        else    return x >> bb[4:0];
            F3_OR:      return (k == KIND_OP && al) ? x | ~bb : x | bb;      // ORN
            default:    return (k == KIND_OP && al) ? x & ~bb : x & bb;      // F3_AND, ANDN
        endcase
    endfunction

    // ALU controls of a kind, as Mig2Decode gives them (kinds of this test only); b_inv for
    // the Zbb ANDN, ORN, XNOR: OP with alt and the funct3 of AND, OR, XOR.
    function automatic alu_ctrl_t alu_of(input kind_e k, input logic al, input logic mm,
                                         input funct3_t f3);
        logic inv;
        inv = k == KIND_OP && al && (f3 == F3_XOR || f3 == F3_OR || f3 == F3_AND);
        case (k)
            KIND_LUI:
                return '{a: A_ZERO, b_imm: 1'b1, op: 1'b0, sub: 1'b0, b_inv: 1'b0, minmax: 1'b0};
            KIND_AUIPC:
                return '{a: A_PC,   b_imm: 1'b1, op: 1'b0, sub: 1'b0, b_inv: 1'b0, minmax: 1'b0};
            KIND_OP:
                return '{a: A_RS1,  b_imm: 1'b0, op: 1'b1, sub: al,   b_inv: inv,  minmax: mm};
            default:
                return '{a: A_RS1,  b_imm: 1'b1, op: 1'b1, sub: 1'b0, b_inv: 1'b0, minmax: 1'b0};
        endcase
    endfunction

    // Apply one case and compare; mm: MIN, MINU, MAX, MAXU (OP, funct3 100..111).
    task automatic check_mm(input kind_e k, input funct3_t f3, input logic al, input logic mm,
                            input word_t x, input word_t y, input word_t im, input iaddr_t p);
        word_t exp;
        dec = '0;
        dec.kind = k; dec.funct3 = f3; dec.alt = al; dec.imm = im;
        dec.alu = alu_of(k, al, mm, f3);
        pc = p; rs1_data = x; rs2_data = y;
        #1;
        exp = model(k, f3, al, mm, x, y, im, {p, 2'b00});
        if (result !== exp)
            $fatal(1, "Mig2Alu: kind=%0d funct3=%0d alt=%b minmax=%b rs1=%h rs2=%h imm=%h pc=%h got %h, expected %h",
                   k, f3, al, mm, x, y, im, {p, 2'b00}, result, exp);
    endtask

    task automatic check(input kind_e k, input funct3_t f3, input logic al, input word_t x,
                         input word_t y, input word_t im, input iaddr_t p);
        check_mm(k, f3, al, 1'b0, x, y, im, p);
    endtask

    // OP operations that have a form with alt: SUB, SRA, ANDN, ORN, XNOR.
    function automatic logic alt_op(input funct3_t f3);
        return f3 == F3_ADD_SUB || f3 == F3_SRL_SRA || f3 == F3_XOR || f3 == F3_OR ||
               f3 == F3_AND;
    endfunction

    // OP-IMM immediate from 12 bits as Mig2Decode gives it (alt is imm[10]).
    function automatic word_t imm12(input logic [11:0] v);
        return {{20{v[11]}}, v};
    endfunction

    initial begin
        edges[0] = 32'h0000_0000; edges[1] = 32'h0000_0001; edges[2] = 32'hffff_ffff;
        edges[3] = 32'h8000_0000; edges[4] = 32'h7fff_ffff; edges[5] = 32'h1234_5678;

        // OP: every operation with edge values; alt for ADD/SUB, SRL/SRA and the logic
        // operations (ANDN, ORN, XNOR).
        for (i = 0; i < 6; i = i + 1)
            for (j = 0; j < 6; j = j + 1)
                for (f = 0; f < 8; f = f + 1) begin
                    check(KIND_OP, f[2:0], 1'b0, edges[i], edges[j], '0, '0);
                    if (alt_op(f[2:0]))
                        check(KIND_OP, f[2:0], 1'b1, edges[i], edges[j], '0, '0);
                    if (f[2])   // MIN, MINU, MAX, MAXU
                        check_mm(KIND_OP, f[2:0], 1'b0, 1'b1, edges[i], edges[j], '0, '0);
                end

        // OP-IMM: edge immediates; shifts with shamt 0, 1, 31.
        for (i = 0; i < 6; i = i + 1) begin
            for (f = 0; f < 8; f = f + 1)
                if (f[2:0] != F3_SLL && f[2:0] != F3_SRL_SRA) begin
                    check(KIND_OP_IMM, f[2:0], 1'b0, edges[i], '0, imm12(12'h000), '0);
                    check(KIND_OP_IMM, f[2:0], 1'b1, edges[i], '0, imm12(12'h7ff), '0);
                    check(KIND_OP_IMM, f[2:0], 1'b0, edges[i], '0, imm12(12'h800), '0);
                    check(KIND_OP_IMM, f[2:0], 1'b1, edges[i], '0, imm12(12'hfff), '0);
                end
            for (j = 0; j < 32; j = j + 31) begin
                check(KIND_OP_IMM, F3_SLL,     1'b0, edges[i], '0, j,           '0);  // SLLI
                check(KIND_OP_IMM, F3_SRL_SRA, 1'b0, edges[i], '0, j,           '0);  // SRLI
                check(KIND_OP_IMM, F3_SRL_SRA, 1'b1, edges[i], '0, 32'h400 | j, '0);  // SRAI
            end
            check(KIND_OP_IMM, F3_SRL_SRA, 1'b1, edges[i], '0, 32'h401, '0);          // SRAI 1
        end

        // LUI and AUIPC.
        check(KIND_LUI,   F3_ADD_SUB, 1'b0, 32'hdead_beef, '0, 32'h1234_5000, '0);
        check(KIND_LUI,   F3_SRL_SRA, 1'b1, 32'hdead_beef, '0, 32'hffff_f000, '0);
        check(KIND_AUIPC, F3_ADD_SUB, 1'b0, 32'hdead_beef, '0, 32'h0000_1000, 30'h0000_0040);
        check(KIND_AUIPC, F3_ADD_SUB, 1'b0, 32'hdead_beef, '0, 32'hffff_f000, 30'h0000_0001);

        // Random cases.
        seed = 1;
        for (i = 0; i < 5000; i = i + 1) begin
            rnd = $random(seed);
            rnd_f3 = rnd[2:0];
            case (rnd[4:3])
                2'd0: if (rnd_f3[2] && rnd[6])  // MIN, MINU, MAX, MAXU
                          check_mm(KIND_OP, rnd_f3, 1'b0, 1'b1, $random(seed), $random(seed),
                                   '0, '0);
                      else
                          check(KIND_OP, rnd_f3, alt_op(rnd_f3) && rnd[5],
                                $random(seed), $random(seed), '0, '0);
                2'd1: if (rnd_f3 == F3_SLL || rnd_f3 == F3_SRL_SRA)
                          check(KIND_OP_IMM, rnd_f3, rnd_f3 == F3_SRL_SRA && rnd[5],
                                $random(seed), '0,
                                {21'h0, rnd_f3 == F3_SRL_SRA && rnd[5], 5'h0, rnd[10:6]}, '0);
                      else
                          check(KIND_OP_IMM, rnd_f3, rnd[21], $random(seed), '0, imm12(rnd[22:11]),
                                '0);
                2'd2: check(KIND_LUI, rnd_f3, 1'b0, $random(seed), '0, {rnd[31:12], 12'h0}, '0);
                2'd3: check(KIND_AUIPC, rnd_f3, 1'b0, $random(seed), '0, {rnd[31:12], 12'h0},
                            rnd[29:0]);
            endcase
        end

        $display("PASS");
        $finish;
    end
endmodule
