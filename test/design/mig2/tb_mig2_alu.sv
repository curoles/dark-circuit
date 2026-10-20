/* Unit test of Mig2Alu.
 *
 * The model computes RV32I results with SystemVerilog operators (+, -, signed and
 * unsigned <, <<, >>, >>>), independent of Alu1 and BarrelShifter. dec is filled
 * directly, like Mig2Decode would: for OP-IMM alt is imm[10], shifts have funct7 in
 * imm[11:5]. Cases: every OP and OP-IMM operation with edge values, LUI, AUIPC,
 * then random cases. Stops at the first mismatch with $fatal.
 */
module TbMig2Alu;
    import Mig2Pkg::*;

    decoded_t    dec;
    logic [31:2] pc;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    wire  [31:0] result;

    logic [31:0] edges [6];
    logic [31:0] rnd;
    integer      i;
    integer      j;
    integer      f;
    integer      seed;

    Mig2Alu u_mig2_alu(.dec(dec), .pc(pc), .rs1_data(rs1_data), .rs2_data(rs2_data), .result(result));

    // Expected result.
    function automatic [31:0] model(input kind_t k, input [2:0] f3, input al, input [31:0] x,
                                    input [31:0] y, input [31:0] im, input [31:0] pcb);
        logic [31:0] bb;
        if (k == KIND_LUI)   return im;
        if (k == KIND_AUIPC) return pcb + im;
        bb = (k == KIND_OP) ? y : im;
        case (f3)
            3'd0:    return (k == KIND_OP && al) ? x - bb : x + bb;
            3'd1:    return x << bb[4:0];
            3'd2:    return ($signed(x) < $signed(bb)) ? 32'd1 : 32'd0;
            3'd3:    return (x < bb) ? 32'd1 : 32'd0;
            3'd4:    return x ^ bb;
            // Not `al ? $signed(x) >>> s : x >> s`: a ?: with an unsigned branch makes
            // the whole expression unsigned, then >>> shifts in zeros.
            3'd5:    if (al) return $signed(x) >>> bb[4:0];
                     else    return x >> bb[4:0];
            3'd6:    return x | bb;
            default: return x & bb;
        endcase
    endfunction

    // Apply one case and compare.
    task automatic check(input kind_t k, input [2:0] f3, input al, input [31:0] x,
                         input [31:0] y, input [31:0] im, input [31:2] p);
        logic [31:0] exp;
        dec = '0;
        dec.kind = k; dec.funct3 = f3; dec.alt = al; dec.imm = im;
        pc = p; rs1_data = x; rs2_data = y;
        #1;
        exp = model(k, f3, al, x, y, im, {p, 2'b00});
        if (result !== exp)
            $fatal(1, "Mig2Alu: kind=%0d funct3=%0d alt=%b rs1=%h rs2=%h imm=%h pc=%h got %h, expected %h",
                   k, f3, al, x, y, im, {p, 2'b00}, result, exp);
    endtask

    // OP-IMM immediate from 12 bits as Mig2Decode gives it, and its alt (imm[10]).
    function automatic [31:0] imm12(input [11:0] v);
        return {{20{v[11]}}, v};
    endfunction

    initial begin
        edges[0] = 32'h0000_0000; edges[1] = 32'h0000_0001; edges[2] = 32'hffff_ffff;
        edges[3] = 32'h8000_0000; edges[4] = 32'h7fff_ffff; edges[5] = 32'h1234_5678;

        // OP: every operation with edge values; alt only for ADD/SUB and SRL/SRA.
        for (i = 0; i < 6; i = i + 1)
            for (j = 0; j < 6; j = j + 1)
                for (f = 0; f < 8; f = f + 1) begin
                    check(KIND_OP, f[2:0], 1'b0, edges[i], edges[j], 32'h0, 30'h0);
                    if (f == 0 || f == 5)
                        check(KIND_OP, f[2:0], 1'b1, edges[i], edges[j], 32'h0, 30'h0);
                end

        // OP-IMM: edge immediates; shifts with shamt 0, 1, 31.
        for (i = 0; i < 6; i = i + 1) begin
            for (f = 0; f < 8; f = f + 1)
                if (f != 1 && f != 5) begin
                    check(KIND_OP_IMM, f[2:0], 1'b0, edges[i], 32'h0, imm12(12'h000), 30'h0);
                    check(KIND_OP_IMM, f[2:0], 1'b1, edges[i], 32'h0, imm12(12'h7ff), 30'h0);
                    check(KIND_OP_IMM, f[2:0], 1'b0, edges[i], 32'h0, imm12(12'h800), 30'h0);
                    check(KIND_OP_IMM, f[2:0], 1'b1, edges[i], 32'h0, imm12(12'hfff), 30'h0);
                end
            for (j = 0; j < 32; j = j + 31) begin
                check(KIND_OP_IMM, 3'd1, 1'b0, edges[i], 32'h0, j,               30'h0);  // SLLI
                check(KIND_OP_IMM, 3'd5, 1'b0, edges[i], 32'h0, j,               30'h0);  // SRLI
                check(KIND_OP_IMM, 3'd5, 1'b1, edges[i], 32'h0, 32'h400 | j,     30'h0);  // SRAI
            end
            check(KIND_OP_IMM, 3'd5, 1'b1, edges[i], 32'h0, 32'h401, 30'h0);              // SRAI 1
        end

        // LUI and AUIPC.
        check(KIND_LUI,   3'd0, 1'b0, 32'hdead_beef, 32'h0, 32'h1234_5000, 30'h0);
        check(KIND_LUI,   3'd5, 1'b1, 32'hdead_beef, 32'h0, 32'hffff_f000, 30'h0);
        check(KIND_AUIPC, 3'd0, 1'b0, 32'hdead_beef, 32'h0, 32'h0000_1000, 30'h0000_0040);
        check(KIND_AUIPC, 3'd0, 1'b0, 32'hdead_beef, 32'h0, 32'hffff_f000, 30'h0000_0001);

        // Random cases.
        seed = 1;
        for (i = 0; i < 5000; i = i + 1) begin
            rnd = $random(seed);
            f = {29'b0, rnd[2:0]};
            case (rnd[4:3])
                2'd0: check(KIND_OP, f[2:0], (f == 0 || f == 5) ? rnd[5] : 1'b0,
                            $random(seed), $random(seed), 32'h0, 30'h0);
                2'd1: if (f == 1 || f == 5)
                          check(KIND_OP_IMM, f[2:0], f == 5 && rnd[5], $random(seed), 32'h0,
                                {21'h0, f == 5 && rnd[5], 5'h0, rnd[10:6]}, 30'h0);
                      else
                          check(KIND_OP_IMM, f[2:0], rnd[21], $random(seed), 32'h0, imm12(rnd[22:11]), 30'h0);
                2'd2: check(KIND_LUI,   f[2:0], 1'b0, $random(seed), 32'h0, {rnd[31:12], 12'h0}, 30'h0);
                2'd3: check(KIND_AUIPC, f[2:0], 1'b0, $random(seed), 32'h0, {rnd[31:12], 12'h0}, rnd[29:0]);
            endcase
        end

        $display("PASS");
        $finish;
    end
endmodule
