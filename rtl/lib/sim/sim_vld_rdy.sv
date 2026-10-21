`ifdef DARK_CIRCUIT_ENABLE_MODULE_TYPE_PARAM
/* Valid/ready source for testbenches: sends the items of its queue (push()) through
 * channel out, raising valid at random: gap_pct is the percent of cycles without an
 * offer while items wait. Follows the valid/ready rules (AGENTS.md) by construction.
 * Random numbers come from $urandom with the simulator's fixed seed: runs repeat.
 */
module SimVldRdySource #(
    parameter type T = logic [7:0]            // type of an item
)(
    input  wire  clk,
    input  wire  rst_n,                       // synchronous reset, active low
    output logic out_valid,                   // channel out
    input  wire  out_ready,
    output T     out_data
);
    T   queue[$];                             // items not offered yet
    int gap_pct = 0;                          // set by the testbench

    function automatic void push(input T item);
        queue.push_back(item);
    endfunction

    always @(posedge clk)
        if (!rst_n)
            out_valid <= 1'b0;
        else if (!out_valid || out_ready) begin     // nothing offered, or it was taken
            if (queue.size() > 0 && $urandom_range(99) >= gap_pct) begin
                out_data  <= queue.pop_front();
                out_valid <= 1'b1;
            end else
                out_valid <= 1'b0;
        end

endmodule

/* Valid/ready sink for testbenches: raises ready at random (ready_pct is the percent
 * of cycles with ready=1), keeps the items it takes (received), and checks the
 * valid/ready rules on its side with $fatal: valid=0 during reset; while valid=1 and
 * ready=0, valid and data must stay until the transfer. ready is a flip-flop, so the
 * sink makes no combinational loop.
 */
module SimVldRdySink #(
    parameter type T = logic [7:0]            // type of an item
)(
    input  wire  clk,
    input  wire  rst_n,                       // synchronous reset, active low
    input  wire  in_valid,                    // channel in
    output logic in_ready,
    input  T     in_data
);
    T     received[$];                        // items taken, in order
    int   ready_pct = 100;                    // set by the testbench
    logic waiting;                            // last cycle: valid=1, ready=0
    T     waiting_data;                       // data of that cycle

    always @(posedge clk) begin
        if (!rst_n && in_valid)
            $fatal(1, "SimVldRdySink: valid=1 during reset");
        if (rst_n && waiting && (!in_valid || in_data !== waiting_data))
            $fatal(1, "SimVldRdySink: valid or data changed before the transfer: valid %b, %h -> %h",
                   in_valid, waiting_data, in_data);
        if (rst_n && in_valid && in_ready)
            received.push_back(in_data);
        waiting      <= rst_n && in_valid && !in_ready;
        waiting_data <= in_data;
        in_ready     <= $urandom_range(99) < ready_pct;
    end

endmodule
`endif
