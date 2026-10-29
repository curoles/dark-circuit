/* Unit test of Mig1Alu.
 *
 * The model computes RV32I results with SystemVerilog operators (+, -, signed and
 * unsigned <, <<, >>, >>>), independent of Alu1 and BarrelShifter. dec is filled
 * directly, like Mig1Decode would: for OP-IMM alt is imm[10], shifts have funct7 in
 * imm[11:5]. Cases: every OP and OP-IMM operation with edge values, LUI, AUIPC,
 * then random cases. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig1Alu;
    import Mig1Pkg::*;
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

    Mig1Alu u_mig1_alu(.dec, .pc, .rs1_data, .rs2_data, .result);

    // Expected result.
    function automatic word_t model(input kind_e k, input funct3_t f3, input logic al,
                                    input word_t x, input word_t y, input word_t im,
                                    input word_t pcb);
        word_t bb;
        if (k == KIND_LUI)   return im;
        if (k == KIND_AUIPC) return pcb + im;
        bb = (k == KIND_OP) ? y : im;
        case (f3)
            F3_ADD_SUB: return (k == KIND_OP && al) ? x - bb : x + bb;
            F3_SLL:     return x << bb[4:0];
            F3_SLT:     return ($signed(x) < $signed(bb)) ? 32'd1 : 32'd0;
            F3_SLTU:    return (x < bb) ? 32'd1 : 32'd0;
            F3_XOR:     return x ^ bb;
            // Not `al ? $signed(x) >>> s : x >> s`: a ?: with an unsigned branch makes
            // the whole expression unsigned, then >>> shifts in zeros.
            F3_SRL_SRA: if (al) return $signed(x) >>> bb[4:0];
                        else    return x >> bb[4:0];
            F3_OR:      return x | bb;
            default:    return x & bb;  // F3_AND
        endcase
    endfunction

    // ALU controls of a kind, as Mig1Decode gives them (kinds of this test only).
    function automatic alu_ctrl_t alu_of(input kind_e k, input logic al);
        case (k)
            KIND_LUI:   return '{a: A_ZERO, b_imm: 1'b1, op: 1'b0, sub: 1'b0};
            KIND_AUIPC: return '{a: A_PC,   b_imm: 1'b1, op: 1'b0, sub: 1'b0};
            KIND_OP:    return '{a: A_RS1,  b_imm: 1'b0, op: 1'b1, sub: al};
            default:    return '{a: A_RS1,  b_imm: 1'b1, op: 1'b1, sub: 1'b0};  // OP-IMM
        endcase
    endfunction

    // Apply one case and compare.
    task automatic check(input kind_e k, input funct3_t f3, input logic al, input word_t x,
                         input word_t y, input word_t im, input iaddr_t p);
        word_t exp;
        dec = '0;
        dec.kind = k; dec.funct3 = f3; dec.alt = al; dec.imm = im; dec.alu = alu_of(k, al);
        pc = p; rs1_data = x; rs2_data = y;
        #1;
        exp = model(k, f3, al, x, y, im, {p, 2'b00});
        if (result !== exp)
            $fatal(1, "Mig1Alu: kind=%0d funct3=%0d alt=%b rs1=%h rs2=%h imm=%h pc=%h got %h, expected %h",
                   k, f3, al, x, y, im, {p, 2'b00}, result, exp);
    endtask

    // Immediate of SRAI: {funct7 of SRAI, shamt}, from its encoding.
    function automatic word_t srai_imm(input logic [4:0] shamt);
        return {20'h0, RiscvInstrPkg::SRAI[31:25], shamt};
    endfunction

    // OP-IMM immediate from 12 bits as Mig1Decode gives it (alt is imm[10]).
    function automatic word_t imm12(input logic [11:0] v);
        return {{20{v[11]}}, v};
    endfunction

    initial begin
        edges[0] = 32'h0000_0000; edges[1] = 32'h0000_0001; edges[2] = 32'hffff_ffff;
        edges[3] = 32'h8000_0000; edges[4] = 32'h7fff_ffff; edges[5] = 32'h1234_5678;

        // OP: every operation with edge values; alt only for ADD/SUB and SRL/SRA.
        for (i = 0; i < 6; i = i + 1)
            for (j = 0; j < 6; j = j + 1)
                for (f = 0; f < 8; f = f + 1) begin
                    check(KIND_OP, f[2:0], 1'b0, edges[i], edges[j], '0, '0);
                    if (f[2:0] == F3_ADD_SUB || f[2:0] == F3_SRL_SRA)
                        check(KIND_OP, f[2:0], 1'b1, edges[i], edges[j], '0, '0);
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
                check(KIND_OP_IMM, F3_SRL_SRA, 1'b1, edges[i], '0, srai_imm(5'(j)), '0);
            end
            check(KIND_OP_IMM, F3_SRL_SRA, 1'b1, edges[i], '0, srai_imm(5'd1), '0);
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
                2'd0: check(KIND_OP, rnd_f3,
                            (rnd_f3 == F3_ADD_SUB || rnd_f3 == F3_SRL_SRA) && rnd[5],
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
