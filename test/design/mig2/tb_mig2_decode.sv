/* Unit test of Mig2Decode.
 *
 * decode.S lists instructions encoded by the assembler, each with its expected
 * decode (see decode.S). For every case the instruction goes to Mig2Decode and the
 * fields that mean something for its kind are compared: kind always; for legal
 * instructions rd_we, uses_rs1 and uses_rs2, then rd and rd_src when rd_we (rd_src
 * expected from the kind: LINK for JAL, JALR, LOAD for loads, else ALU), rs1 when uses_rs1,
 * rs2 when uses_rs2, funct3 when the kind has it, alt for OP and OP-IMM shifts,
 * imm when the kind has an immediate (the CSR address for CSR instructions).
 * At the end every kind must have had a case.
 * Loads +hex=<file> into a SimROM and reads it with peek().
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig2Decode;
    import Mig2Pkg::*;

    localparam AW     = MIG2_CFG.mem_addr_width;
    localparam FIELDS = 10;                  // expected values after the instruction
    localparam CASE   = 4 * (1 + FIELDS);    // bytes of one case

    // Cases are read with peek(), the read port is not used.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0]  rom_data;
    /* verilator lint_on UNUSEDSIGNAL */
    insn_t       insn;
    decoded_t    dec;

    string       hex;
    integer      n;
    integer      c;
    integer      k;
    integer      addr;
    logic [31:0] e [FIELDS];  // expected: kind, rd_we, uses_rs1, uses_rs2, rd, rs1, rs2, funct3, alt, imm
    kind_e       exp_kind;    // kind expected, from the case file
    logic [31:0] tested;      // tested[k]: kind k had a case

    SimROM #(.DATA_SIZE(4), .ADDR_WIDTH(AW)) u_cases(
        .clk(1'b0), .en(1'b0), .addr({(AW-2){1'b0}}), .data(rom_data));

    Mig2Decode u_mig2_decode(.insn(insn), .dec(dec));

    // Word at byte address a, little-endian.
    function automatic [31:0] word(input integer a);
        // Only the AW low bits of the address reach the memory.
        /* verilator lint_off UNUSEDSIGNAL */
        integer ab;
        /* verilator lint_on UNUSEDSIGNAL */
        for (int b = 0; b < 4; b++) begin
            ab = a + b;
            word[8*b +: 8] = u_cases.peek(ab[AW-1:0]);
        end
    endfunction

    // Kinds that have funct3, and kinds that have an immediate.
    function automatic logic has_funct3(input kind_e kind);
        case (kind)
            KIND_JALR, KIND_BRANCH, KIND_LOAD, KIND_STORE, KIND_OP_IMM, KIND_OP, KIND_FENCE,
            KIND_CSR, KIND_MULDIV:                                                         return 1'b1;
            default:                                                                       return 1'b0;
        endcase
    endfunction

    function automatic logic has_imm(input kind_e kind);
        case (kind)
            KIND_LUI, KIND_AUIPC, KIND_JAL, KIND_JALR, KIND_BRANCH, KIND_LOAD, KIND_STORE, KIND_OP_IMM,
            KIND_CSR:                                                                                  return 1'b1;
            default:                                                                                   return 1'b0;
        endcase
    endfunction

    // Source of rd expected for a kind that writes rd.
    function automatic rd_src_e rd_src_of(input kind_e kind);
        case (kind)
            KIND_JAL, KIND_JALR: return RD_LINK;
            KIND_LOAD:           return RD_LOAD;
            KIND_CSR:            return RD_CSR;
            KIND_MULDIV:         return RD_MULDIV;
            default:             return RD_ALU;
        endcase
    endfunction

    // Controls expected for a kind: a model of its own, not a copy of Mig2Decode's table.
    function automatic logic uses_alu(input kind_e kind);
        case (kind)
            KIND_LUI, KIND_AUIPC, KIND_LOAD, KIND_STORE, KIND_OP_IMM, KIND_OP: return 1'b1;
            default:                                                         return 1'b0;
        endcase
    endfunction

    function automatic alu_ctrl_t alu_of(input kind_e kind, input logic alt);
        case (kind)
            KIND_LUI:    return '{a: A_ZERO, b_imm: 1'b1, op: 1'b0, sub: 1'b0};
            KIND_AUIPC:  return '{a: A_PC,   b_imm: 1'b1, op: 1'b0, sub: 1'b0};
            KIND_OP:     return '{a: A_RS1,  b_imm: 1'b0, op: 1'b1, sub: alt};
            KIND_OP_IMM: return '{a: A_RS1,  b_imm: 1'b1, op: 1'b1, sub: 1'b0};
            default:     return '{a: A_RS1,  b_imm: 1'b1, op: 1'b0, sub: 1'b0};  // address rs1 + imm
        endcase
    endfunction

    function automatic br_ctrl_t br_of(input kind_e kind);
        case (kind)
            KIND_JAL:    return '{jump: 1'b1, branch: 1'b0, target_rs1: 1'b0};
            KIND_JALR:   return '{jump: 1'b1, branch: 1'b0, target_rs1: 1'b1};
            KIND_BRANCH: return '{jump: 1'b0, branch: 1'b1, target_rs1: 1'b0};
            default:     return '0;
        endcase
    endfunction

    function automatic mem_ctrl_t mem_of(input kind_e kind);
        return '{read: kind == KIND_LOAD, write: kind == KIND_STORE};
    endfunction

    function automatic sys_ctrl_t sys_of(input kind_e kind);
        return '{csr: kind == KIND_CSR, mret: kind == KIND_MRET, ecall: kind == KIND_ECALL,
                 ebreak: kind == KIND_EBREAK, illegal: kind == KIND_ILLEGAL};
    endfunction

    // M controls expected: from the bits of funct3 (MUL 000, MULH 001, MULHSU 010,
    // MULHU 011, DIV 100, DIVU 101, REM 110, REMU 111).
    function automatic muldiv_ctrl_t muldiv_of(input kind_e kind, input logic [2:0] f3);
        if (kind != KIND_MULDIV)
            return '0;
        return '{en: 1'b1, div: f3[2], rem: f3[2] && f3[1], mul_lo: f3 == 3'b000,
                 a_signed: f3 == 3'b001 || f3 == 3'b010, b_signed: f3 == 3'b001,
                 div_signed: f3[2] && !f3[0]};
    endfunction

    // Compare one field of case cn with instruction w.
    task automatic check(input integer cn, input [31:0] w, input string field, input [31:0] got, input [31:0] exp);
        if (got !== exp)
            $fatal(1, "Mig2Decode case %0d, insn %h: %s got %h, expected %h", cn, w, field, got, exp);
    endtask

    initial begin
        if (!$value$plusargs("hex=%s", hex))
            $fatal(1, "Mig2Decode: plusarg +hex=<file> is missing");
        if (u_cases.load(hex, u_cases.VLOG_HEX_FORMAT) != 1)
            $fatal(1, "Mig2Decode: load() of %s returned 0", hex);

        tested = '0;
        n = word(0);
        for (c = 0; c < n; c = c + 1) begin
            addr = 4 + c * CASE;
            insn = word(addr);
            for (k = 0; k < FIELDS; k = k + 1)
                e[k] = word(addr + 4 + 4 * k);
            exp_kind = kind_e'(e[0][4:0]);
            #1;
            check(c, insn, "kind", {27'b0, dec.kind}, e[0]);
            check(c, insn, "br",     32'(dec.br),     32'(br_of(exp_kind)));
            check(c, insn, "mem",    32'(dec.mem),    32'(mem_of(exp_kind)));
            check(c, insn, "sys",    32'(dec.sys),    32'(sys_of(exp_kind)));
            check(c, insn, "muldiv", 32'(dec.muldiv), 32'(muldiv_of(exp_kind, e[7][2:0])));
            if (uses_alu(exp_kind))
                check(c, insn, "alu", 32'(dec.alu), 32'(alu_of(exp_kind, e[8][0])));
            if (exp_kind != KIND_ILLEGAL) begin
                check(c, insn, "rd_we",    {31'b0, dec.rd_we},    e[1]);
                check(c, insn, "uses_rs1", {31'b0, dec.uses_rs1}, e[2]);
                check(c, insn, "uses_rs2", {31'b0, dec.uses_rs2}, e[3]);
                if (e[1][0]) check(c, insn, "rd",  {27'b0, dec.rd},  e[4]);
                if (e[1][0]) check(c, insn, "rd_src", {29'b0, dec.rd_src}, {29'b0, rd_src_of(exp_kind)});
                if (e[2][0]) check(c, insn, "rs1", {27'b0, dec.rs1}, e[5]);
                if (e[3][0]) check(c, insn, "rs2", {27'b0, dec.rs2}, e[6]);
                if (has_funct3(exp_kind))
                    check(c, insn, "funct3", {29'b0, dec.funct3}, e[7]);
                if (exp_kind == KIND_OP || (exp_kind == KIND_OP_IMM && (e[7] == 1 || e[7] == 5)))
                    check(c, insn, "alt", {31'b0, dec.alt}, e[8]);
                if (has_imm(exp_kind))
                    check(c, insn, "imm", dec.imm, e[9]);
            end
            tested[exp_kind] = 1'b1;
        end

        for (k = 0; k <= KIND_MULDIV; k = k + 1)
            if (!tested[k])
                $fatal(1, "Mig2Decode: no case of kind %0d", k);
        $display("PASS: %0d cases", n);
        $finish;
    end
endmodule
