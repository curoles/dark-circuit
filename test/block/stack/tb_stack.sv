/* Test of Stack.
 *
 * Random pushes, pops and both together, in phases that push more or pop more, so that the
 * stack runs full and empty again and again. A model of its own (the entries from the
 * bottom up, a count) checks after every clock empty, full, count and the top entry. In the
 * end the test checks that every case happened: pushes and pops, replaces (push and pop),
 * a push and pop on an empty stack, pops when empty, pushes when full (ignored, or with
 * OVERWRITE=1 overwriting the oldest), full and empty reached. One reset in the middle
 * empties the stack.
 * Runs three stacks: 8 entries without OVERWRITE, 8 of 30 bits with OVERWRITE (the size of
 * the return-address stack of Mig2), 2 entries with OVERWRITE; 20000 clocks on Verilator.
 * Icarus, slow on the gates of the struct version, runs 2000 clocks without the 30-bit one.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbStackCheck #(
    parameter ADDR_WIDTH = 3,
    parameter DATA_WIDTH = 8,       // up to 32
    parameter OVERWRITE  = 0
)(
    input  wire  clk,
    output logic done
);
    localparam DEPTH    = 1 << ADDR_WIDTH;
`ifdef VERILATOR
    localparam N_CLOCKS = 20000;
`else
    localparam N_CLOCKS = 2000;
`endif

    typedef logic [DATA_WIDTH-1:0] data_t;

    logic                rst_n;
    logic                push;
    data_t               data_in;
    logic                pop;
    data_t               data_out;
    wire                 empty;
    wire                 full;
    wire [ADDR_WIDTH:0]  count;

    // Model: m_entry[0] is the bottom, m_entry[m_count-1] the top.
    bit [DATA_WIDTH-1:0] m_entry [DEPTH];
    integer              m_count;
    integer              seed;

    // Cases seen.
    integer n_push;
    integer n_pop;
    integer n_replace;
    integer n_push_pop_empty;
    integer n_pop_empty;
    integer n_push_full;
    integer n_full;
    integer n_empty_after_full;
    logic   was_full;

    Stack #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .OVERWRITE(OVERWRITE)) u_stack(
        .clk, .rst_n, .push, .data_in, .pop, .data_out, .empty, .full, .count);

    // After a rising edge: the outputs are those of the model.
    task automatic check;
        if (empty !== (m_count == 0) || full !== (m_count == DEPTH) ||
            count !== m_count[ADDR_WIDTH:0] || (m_count > 0 && data_out !== m_entry[m_count-1]))
            $fatal(1, "Stack %0d %0d: empty %b full %b count %0d top %h, expected %b %b %0d %h",
                   DEPTH, OVERWRITE, empty, full, count, data_out, m_count == 0,
                   m_count == DEPTH, m_count, m_count > 0 ? m_entry[m_count-1] : '0);
    endtask

    // Model of one rising edge with the inputs of this cycle.
    task automatic model_edge;
        if (!rst_n) begin
            m_count = 0;
            return;
        end
        if (push && pop && m_count > 0) begin
            m_entry[m_count-1] = data_in;
            n_replace = n_replace + 1;
        end else if (push) begin
            if (pop)
                n_push_pop_empty = n_push_pop_empty + 1;
            if (m_count < DEPTH) begin
                m_entry[m_count] = data_in;
                m_count = m_count + 1;
                n_push = n_push + 1;
            end else begin
                n_push_full = n_push_full + 1;
                if (OVERWRITE != 0) begin   // the oldest goes, the others move down
                    for (int i = 1; i < DEPTH; i++)
                        m_entry[i-1] = m_entry[i];
                    m_entry[DEPTH-1] = data_in;
                end
            end
        end else if (pop) begin
            if (m_count > 0) begin
                m_count = m_count - 1;
                n_pop = n_pop + 1;
            end else
                n_pop_empty = n_pop_empty + 1;
        end
        if (m_count == DEPTH) begin
            n_full   = n_full + 1;
            was_full = 1'b1;
        end
        if (m_count == 0 && was_full) begin
            n_empty_after_full = n_empty_after_full + 1;
            was_full = 1'b0;
        end
    endtask

    task automatic random_test;
        // Bits of r: 0..3 push, 4..7 pop; the rest unused.
        /* verilator lint_off UNUSEDSIGNAL */
        integer r;
        /* verilator lint_on UNUSEDSIGNAL */
        logic   push_more;      // phase: pushes more often than pops, or the other way
        for (int k = 0; k < N_CLOCKS; k++) begin
            r         = $random(seed);
            push_more = (k / (4 * DEPTH)) % 2 == 0;
            rst_n     = (k != N_CLOCKS / 2);
            push      = push_more ? r[3:0] < 4'd10 : r[3:0] < 4'd5;
            pop       = push_more ? r[7:4] < 4'd5 : r[7:4] < 4'd10;
            data_in   = DATA_WIDTH'($random(seed));
            model_edge();
            @(negedge clk);
            check();
        end
        rst_n = 1'b1;
        push  = 1'b0;
        pop   = 1'b0;
    endtask

    initial begin
        done = 1'b0;
        seed = DEPTH + OVERWRITE;
        n_push             = 0;
        n_pop              = 0;
        n_replace          = 0;
        n_push_pop_empty   = 0;
        n_pop_empty        = 0;
        n_push_full        = 0;
        n_full             = 0;
        n_empty_after_full = 0;
        was_full           = 1'b0;
        m_count            = 0;
        rst_n   = 1'b0;
        push    = 1'b0;
        pop     = 1'b0;
        data_in = '0;
        // Reset: empty.
        @(negedge clk);
        model_edge();
        @(negedge clk);
        check();
        random_test();
        if (n_push == 0 || n_pop == 0 || n_replace == 0 || n_push_pop_empty == 0 ||
            n_pop_empty == 0 || n_push_full == 0 || n_full == 0 || n_empty_after_full == 0)
            $fatal(1, "Stack %0d %0d: a case did not happen: push %0d pop %0d replace %0d %s %0d %0d %0d %0d %0d",
                   DEPTH, OVERWRITE, n_push, n_pop, n_replace,
                   "push-pop empty, pop empty, push full, full, empty", n_push_pop_empty,
                   n_pop_empty, n_push_full, n_full, n_empty_after_full);
        done = 1'b1;
    end
endmodule

module TbStack;
`ifdef VERILATOR
    localparam bit WIDE = 1'b1;     // also the 30-bit stack
`else
    localparam bit WIDE = 1'b0;
`endif
    wire clk;
    wire done_8;
    wire done_8w;
    wire done_2w;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbStackCheck #(.ADDR_WIDTH(3), .DATA_WIDTH(8), .OVERWRITE(0)) u_check_8(
        .clk, .done(done_8));
    if (WIDE) begin: g_wide
        TbStackCheck #(.ADDR_WIDTH(3), .DATA_WIDTH(30), .OVERWRITE(1)) u_check_8w(
            .clk, .done(done_8w));
    end else begin: g_narrow
        assign done_8w = 1'b1;
    end
    TbStackCheck #(.ADDR_WIDTH(1), .DATA_WIDTH(8), .OVERWRITE(1)) u_check_2w(
        .clk, .done(done_2w));

    initial begin
        wait (done_8 && done_8w && done_2w);
        $display("PASS");
        $finish;
    end
endmodule
