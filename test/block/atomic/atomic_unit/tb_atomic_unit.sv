/* Test of AtomicUnit, behave or struct version.
 *
 * The testbench is the requester and the memory. The requester offers random requests
 * (nothing, a read or a write of a line, or an atomic operation of every kind on a word of a
 * line) and holds one that is not taken. The memory is ready in 70 % of the clocks, writes
 * at the clock it takes a write, and answers each read with the line as it was then, 1 to 4
 * clocks later, in order. Model: an ideal memory changed at the clock the unit takes a
 * request (a write: its bytes; an atomic: its word gets op(old, operand), computed here
 * without Alu2), and the answers expected in order (a read: the line; an atomic: the line
 * before). Every answer is compared, and at the end the memory with the ideal one. 3000
 * clocks on Verilator, 400 on Icarus; beats of 64 bits with words of 32, of 32 with 32, of
 * 64 with 64. Every case must happen (checks named cover): each of the 9 operations, an
 * atomic request waiting for the answers of reads, a read and a write passing. Checks named
 * model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbAtomicUnitCheck import AtomicPkg::*; #(
    parameter DATA_WIDTH = 64,
    parameter ATOM_WIDTH = 32
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
`ifdef VERILATOR
    localparam N_CYCLES = 3000;
`else
    localparam N_CYCLES = 400;
`endif
    localparam AW          = 12;
    localparam SW          = DATA_WIDTH / 8;
    localparam LINE_BYTES  = DATA_WIDTH / 8;
    localparam LINE_OFF    = $clog2(LINE_BYTES);
    localparam LINES       = 8;
    localparam LANES       = DATA_WIDTH / ATOM_WIDTH;
    localparam ATOM_BYTES  = ATOM_WIDTH / 8;
    localparam ATOM_OFFSET = $clog2(ATOM_BYTES);
    localparam QD          = 16;
    localparam ED          = 64;

    typedef logic [DATA_WIDTH-1:0] line_t;
    typedef logic [ATOM_WIDTH-1:0] word_t;

    logic            req_valid;
    wire             req_ready;
    logic            req_we;
    logic [AW-1:0]   req_addr;
    logic [2:0]      req_size;
    atop_t           req_atop;
    line_t           req_wdata;
    logic [SW-1:0]   req_wstrb;
    wire             rsp_valid;
    wire  [DATA_WIDTH-1:0] rsp_data;
    wire             mem_req_valid;
    logic            mem_req_ready;
    wire             mem_req_we;
    wire  [AW-1:0]   mem_req_addr;
    wire  [2:0]      mem_req_size;
    wire  [DATA_WIDTH-1:0] mem_req_wdata;
    wire  [SW-1:0]   mem_req_wstrb;
    logic            mem_rsp_valid;
    line_t           mem_rsp_data;
    integer          seed;

    AtomicUnit #(.ADDR_WIDTH(AW), .DATA_WIDTH(DATA_WIDTH), .ATOM_WIDTH(ATOM_WIDTH)) u_atomic_unit(
        .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_addr, .req_size, .req_atop,
        .req_wdata, .req_wstrb, .rsp_valid, .rsp_data, .mem_req_valid, .mem_req_ready,
        .mem_req_we, .mem_req_addr, .mem_req_size, .mem_req_wdata, .mem_req_wstrb,
        .mem_rsp_valid, .mem_rsp_data);

    line_t mem   [LINES];       // the memory
    line_t ideal [LINES];       // the model
    line_t rq_data [QD];        // reads the memory took, not answered
    int    rq_due  [QD];
    int    rq_head, rq_tail;
    line_t ex [ED];             // answers expected
    int    ex_head, ex_tail;
    int    cyc;
    logic [8:0] seen_op;        // each operation, in the order of ops
    logic  seen_wait, seen_read, seen_write;

    atop_t ops [9];

    function automatic line_t merge(input line_t old, input line_t d, input logic [SW-1:0] s);
        line_t l;
        l = old;
        for (int b = 0; b < SW; b++)
            if (s[b])
                l[8*b +: 8] = d[8*b +: 8];
        return l;
    endfunction

    // What an atomic writes: the model, written apart from the unit's Alu2.
    function automatic word_t apply(input atop_t a, input word_t old, input word_t d);
        case (a)
            ATOP_LD_ADD:  return old + d;
            ATOP_LD_CLR:  return old & ~d;
            ATOP_LD_EOR:  return old ^ d;
            ATOP_LD_SET:  return old | d;
            ATOP_LD_SMAX: return ($signed(old) > $signed(d)) ? old : d;
            ATOP_LD_SMIN: return ($signed(old) < $signed(d)) ? old : d;
            ATOP_LD_UMAX: return (old > d) ? old : d;
            ATOP_LD_UMIN: return (old < d) ? old : d;
            default:      return d;     // ATOP_SWAP
        endcase
    endfunction

    function automatic line_t random_line();
        line_t l;
        for (int i = 0; i < DATA_WIDTH; i += 32)
            l[i +: 32] = $random(seed);
        return l;
    endfunction

    // Reads that passed and are not answered, in the model.
    function automatic int pass_pending();
        return ex_tail - ex_head;
    endfunction

    task automatic new_request();
        int k, lane;
        k         = {$random(seed)} % 8;
        req_valid = k != 0;
        req_wdata = random_line();
        req_wstrb = SW'($random(seed));
        req_addr  = AW'(({$random(seed)} % LINES) << LINE_OFF);
        req_size  = 3'(LINE_OFF);
        req_atop  = ATOP_NONE;
        req_we    = k == 1 || k == 2;
        if (k >= 5) begin                   // an atomic operation on a word
            lane      = {$random(seed)} % LANES;
            req_we    = 1'b0;
            req_atop  = ops[{$random(seed)} % 9];
            req_addr  = req_addr | AW'(lane << ATOM_OFFSET);
            req_size  = 3'(ATOM_OFFSET);
        end
    endtask

    initial begin
        logic  taken, mem_take;
        logic [$clog2(LINES)-1:0] l;
        int    lane, i;
        line_t row;
        word_t old;
        done = 1'b0;
        ops = '{ATOP_LD_ADD, ATOP_LD_CLR, ATOP_LD_EOR, ATOP_LD_SET, ATOP_LD_SMAX, ATOP_LD_SMIN,
                ATOP_LD_UMAX, ATOP_LD_UMIN, ATOP_SWAP};
        seed = DATA_WIDTH + ATOM_WIDTH;
        for (int k = 0; k < LINES; k++) begin
            mem[k]   = random_line();
            ideal[k] = mem[k];
        end
        rq_head = 0;
        rq_tail = 0;
        ex_head = 0;
        ex_tail = 0;
        cyc = 0;
        seen_op = '0;
        {seen_wait, seen_read, seen_write} = '0;
        mem_req_ready = 1'b0;
        mem_rsp_valid = 1'b0;
        mem_rsp_data  = '0;
        new_request();
        req_valid = 1'b0;       // nothing offered before the model runs
        @(posedge rst_n);
        @(posedge clk);
        #1;
        new_request();
        for (int k = 0; k < N_CYCLES; k++) begin
            @(negedge clk);
            // The answers.
            if (rsp_valid !== mem_rsp_valid || (rsp_valid && rsp_data !== ex[ex_head % ED]))
                `DC_TEST_FAIL(model, $sformatf({
                    "AtomicUnit %0d/%0d: rsp %b %h, expected %h"}, DATA_WIDTH, ATOM_WIDTH,
                    rsp_valid, rsp_data, ex[ex_head % ED]))
            if (rsp_valid)
                ex_head = ex_head + 1;
            // The request the unit takes: the model changes now.
            taken = req_valid && req_ready;
            l     = req_addr[LINE_OFF +: $clog2(LINES)];
            if (req_valid && is_atomic(req_atop) && pass_pending() > 0)
                seen_wait = 1'b1;
            if (taken && is_atomic(req_atop)) begin
                lane = (int'(req_addr) >> ATOM_OFFSET) % LANES;
                row  = ideal[l];
                ex[ex_tail % ED] = row;
                ex_tail = ex_tail + 1;
                old = row[ATOM_WIDTH * lane +: ATOM_WIDTH];
                row[ATOM_WIDTH * lane +: ATOM_WIDTH] =
                    apply(req_atop, old, req_wdata[ATOM_WIDTH * lane +: ATOM_WIDTH]);
                ideal[l] = row;
                for (i = 0; i < 9; i++)
                    if (ops[i] == req_atop)
                        seen_op[i] = 1'b1;
            end else if (taken && req_we) begin
                ideal[l] = merge(ideal[l], req_wdata, req_wstrb);
                seen_write = 1'b1;
            end else if (taken) begin
                ex[ex_tail % ED] = ideal[l];
                ex_tail = ex_tail + 1;
                seen_read = 1'b1;
            end
            // The memory: a write now, a read answered later with the line of now.
            mem_take = mem_req_valid && mem_req_ready;
            l        = mem_req_addr[LINE_OFF +: $clog2(LINES)];
            if (mem_req_valid &&
                (int'(mem_req_addr) & ((1 << int'(mem_req_size)) - 1)) != 0)
                `DC_TEST_FAIL(model, $sformatf({
                    "AtomicUnit %0d/%0d: mem_req %h not aligned to size %0d"},
                    DATA_WIDTH, ATOM_WIDTH, mem_req_addr, mem_req_size))
            if (mem_take && mem_req_we)
                mem[l] = merge(mem[l], mem_req_wdata, mem_req_wstrb);
            else if (mem_take) begin
                rq_data[rq_tail % QD] = mem[l];
                rq_due[rq_tail % QD]  = cyc + 1 + {$random(seed)} % 4;
                rq_tail = rq_tail + 1;
            end
            @(posedge clk);
            #1;
            cyc = cyc + 1;
            mem_rsp_valid = 1'b0;
            if (rq_head != rq_tail && rq_due[rq_head % QD] <= cyc) begin
                mem_rsp_valid = 1'b1;
                mem_rsp_data  = rq_data[rq_head % QD];
                rq_head = rq_head + 1;
            end
            // The last clocks offer nothing: what is in flight (an atomic's write) finishes
            // before the memory is compared.
            if (taken || !req_valid) begin
                if (k < N_CYCLES - 30)
                    new_request();
                else
                    req_valid = 1'b0;
            end
            mem_req_ready = ({$random(seed)} % 10) < 7;
        end
        for (int k = 0; k < LINES; k++)
            if (mem[k] !== ideal[k])
                `DC_TEST_FAIL(model, $sformatf("AtomicUnit %0d/%0d: line %0d is %h, expected %h",
                    DATA_WIDTH, ATOM_WIDTH, k, mem[k], ideal[k]))
        if (seen_op !== '1 || !seen_wait || !seen_read || !seen_write)
            `DC_TEST_FAIL(cover, $sformatf("AtomicUnit %0d/%0d: ops %b wait %b read %b write %b",
                DATA_WIDTH, ATOM_WIDTH, seen_op, seen_wait, seen_read, seen_write))
        done = 1'b1;
    end
endmodule

module TbAtomicUnit;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  [2:0] done;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbAtomicUnitCheck #(.DATA_WIDTH(64), .ATOM_WIDTH(32)) u_check_64_32(
        .clk, .rst_n, .done(done[0]));
    TbAtomicUnitCheck #(.DATA_WIDTH(32), .ATOM_WIDTH(32)) u_check_32_32(
        .clk, .rst_n, .done(done[1]));
    TbAtomicUnitCheck #(.DATA_WIDTH(64), .ATOM_WIDTH(64)) u_check_64_64(
        .clk, .rst_n, .done(done[2]));

    initial begin
        wait (done == '1);
        $display("PASS");
        $finish;
    end
endmodule
