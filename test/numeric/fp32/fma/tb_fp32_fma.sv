/* Test of Fp32Fma against TestFloat: f32_mulAdd as all four fused forms, f32_add, f32_sub
 * and f32_mul, in the five rounding modes, streamed through the pipeline.
 *
 * STAGES (the define FMA_STAGES, default 0) is Fp32Fma's. +cases=<dir>: the case files
 * <dir>/<function>.<mode> that testfloat_gen wrote (dc_testfloat_cases,
 * cmake/testfloat.cmake), a line per case in hex: the operands, the fp32 result, the flags
 * (SoftFloat's bits, FpPkg::flags_t's order). A function's five mode files are read a line of
 * each in turn, so the rounding mode changes from one operation to the next.
 * An operation enters at every falling edge (in_valid=1), its expected result and flags go
 * into a queue; out_valid must come STAGES edges later, for every operation and only for
 * them, and then the result and all five flags must be the queue's oldest. So operations
 * that follow each other with different operands, forms and modes are in the pipeline
 * together: a stage that reads a value of a later operation instead of the one its
 * boundary carries gives a wrong result (with STAGES 0 nothing is in flight).
 * A case of f32_mulAdd (a * b + c = z) enters four times, the operand signs flipped so that
 * every form gives z: MADD(a, b, c), MSUB(a, b, -c), NMSUB(-a, b, c), NMADD(-a, b, -c)
 * (flipping a NaN's sign keeps it a NaN of its kind). ADD, SUB and MUL get c = a
 * signalling NaN, which they must not use (no NV from it). +limit=<n>: about n operations a
 * function at most (the streamed builds: their point is overlap, not more cases; STAGES 0
 * reads all and needs no clock between operations). Every file must have cases.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbFp32Fma;
    import Fp32Pkg::*;
    import FpPkg::*;

`ifdef FMA_STAGES
    localparam int STAGES = `FMA_STAGES;
`else
    localparam int STAGES = 0;
`endif
    localparam int          MODES = 5;
    localparam logic [31:0] SIGN  = 32'h8000_0000;
    localparam logic [31:0] SNAN  = 32'h7fa0_0000;  // c of ADD, SUB, MUL: not used

    // An operation in flight: its inputs (for the message) and what must come out.
    typedef struct packed {
        fma_op_e     op;
        rm_e         rm;
        logic [31:0] a;
        logic [31:0] b;
        logic [31:0] c;
        logic [31:0] want;
        logic [7:0]  want_flags;
    } flight_t;

    logic        clk;
    logic        rst_n;
    logic        in_valid;
    fp32_t       a;
    fp32_t       b;
    fp32_t       c;
    fma_op_e     op;
    rm_e         rm;
    logic        out_valid;
    fp32_t       result;
    flags_t      flags;

    flight_t     in_flight [$];
    string       dir;
    string       func;          // the function being read
    integer      fd [MODES];
    integer      n;             // operations of a function
    integer      limit;         // +limit=<n>: at most about n operations a function (0: all)
    integer      total;
    logic [31:0] va;
    logic [31:0] vb;
    logic [31:0] vc;
    logic [31:0] want;
    logic [7:0]  want_flags;

    Fp32Fma #(.STAGES(STAGES)) u_fp32_fma(
        .clk, .rst_n, .in_valid, .a, .b, .c, .op, .rm, .out_valid, .result, .flags);

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic rm_e mode(input int m);
        case (m)
            0:       return RM_RNE;
            1:       return RM_RTZ;
            2:       return RM_RDN;
            3:       return RM_RUP;
            default: return RM_RMM;
        endcase
    endfunction

    function automatic string suffix(input int m);
        case (m)
            0:       return "rne";
            1:       return "rtz";
            2:       return "rdn";
            3:       return "rup";
            default: return "rmm";
        endcase
    endfunction

    // After the inputs of this edge settled: out_valid must be as expected (entering: the
    // queue holds more than STAGES; draining: any), and with it the oldest operation's result.
    task automatic check_out(input logic draining);
        flight_t f;
        logic    expect_valid;
        expect_valid = draining ? in_flight.size() > 0 : in_flight.size() > STAGES;
        if (out_valid !== expect_valid)
            $fatal(1, "Fp32Fma %0d %s: out_valid %b, expected %b (%0d in flight)", STAGES, func,
                   out_valid, expect_valid, in_flight.size());
        if (out_valid) begin
            f = in_flight.pop_front();
            if (result !== f.want || {3'b0, flags} !== f.want_flags)
                $fatal(1, "Fp32Fma %0d %s %s %s: a %h b %h c %h -> %h flags %b, expected %h flags %b",
                       STAGES, func, f.op.name(), f.rm.name(), f.a, f.b, f.c, result, flags,
                       f.want, f.want_flags);
        end
    endtask

    // One operation enters at this falling edge; the next edge follows.
    task automatic issue(input fma_op_e o, input rm_e m, input logic [31:0] x,
                         input logic [31:0] y, input logic [31:0] z);
        in_valid = 1'b1;
        op       = o;
        rm       = m;
        a        = x;
        b        = y;
        c        = z;
        in_flight.push_back('{op: o, rm: m, a: x, b: y, c: z, want: want,
                              want_flags: want_flags});
        #1;
        check_out(1'b0);
        // Combinational: no clock edge needed (fewer events, a faster test).
        if (STAGES == 0)
            #1;
        else
            @(negedge clk);
    endtask

    // Open function f's five mode files.
    task automatic open(input string f);
        func = f;
        n    = 0;
        for (int m = 0; m < MODES; m++) begin
            fd[m] = $fopen({dir, "/", f, ".", suffix(m)}, "r");
            if (fd[m] == 0)
                $fatal(1, "Fp32Fma: can not open %s/%s.%s", dir, f, suffix(m));
        end
    endtask

    task automatic close();
        for (int m = 0; m < MODES; m++)
            $fclose(fd[m]);
        if (n == 0)
            $fatal(1, "Fp32Fma: no cases of %s", func);
        total += n;
    endtask

    initial begin
        logic more;
        if (!$value$plusargs("cases=%s", dir))
            $fatal(1, "Fp32Fma: plusarg +cases=<dir> is missing");
        rst_n    = 1'b0;
        in_valid = 1'b0;
        a        = '0;
        b        = '0;
        c        = '0;
        op       = FMA_MADD;
        rm       = RM_RNE;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        total = 0;
        if (!$value$plusargs("limit=%d", limit))
            limit = 0;

        open("f32_mulAdd");
        more = 1'b1;
        while (more && (limit == 0 || n < limit))
            for (int m = 0; m < MODES && more; m++)
                if ($fscanf(fd[m], "%h %h %h %h %h\n", va, vb, vc, want, want_flags) == 5) begin
                    issue(FMA_MADD, mode(m), va, vb, vc);
                    issue(FMA_MSUB, mode(m), va, vb, vc ^ SIGN);
                    issue(FMA_NMSUB, mode(m), va ^ SIGN, vb, vc);
                    issue(FMA_NMADD, mode(m), va ^ SIGN, vb, vc ^ SIGN);
                    n += 4;
                end else
                    more = 1'b0;
        close();
        for (int k = 0; k < 3; k++) begin   // f32_add, f32_sub, f32_mul
            open(k == 0 ? "f32_add" : k == 1 ? "f32_sub" : "f32_mul");
            more = 1'b1;
            while (more && (limit == 0 || n < limit))
                for (int m = 0; m < MODES && more; m++)
                    if ($fscanf(fd[m], "%h %h %h %h\n", va, vb, want, want_flags) == 4) begin
                        issue(k == 0 ? FMA_ADD : k == 1 ? FMA_SUB : FMA_MUL, mode(m), va, vb,
                              SNAN);
                        n++;
                    end else
                        more = 1'b0;
            close();
        end

        // Drain: the last operations come out, nothing enters.
        in_valid = 1'b0;
        while (in_flight.size() > 0) begin
            #1;
            check_out(1'b1);
            @(negedge clk);
        end
        #1;
        if (out_valid !== 1'b0)
            $fatal(1, "Fp32Fma %0d: out_valid after the last operation", STAGES);
        $display("PASS: %0d operations, STAGES %0d", total, STAGES);
        $finish;
    end
endmodule
