/* Stack (last in, first out) for small depths, behavioral.
 *
 * Entries are flops, so use it for small depths. data_out is the top entry, the newest,
 * while empty is 0. push=1 adds data_in on rising edge, pop=1 removes the top. push and pop
 * in the same cycle replace the top with data_in (count stays); on an empty stack only the
 * push happens. A pop is ignored when empty. A push when full is ignored, or with
 * OVERWRITE=1 overwrites the oldest entry (count stays full): the stack keeps the newest
 * entries, as a return-address stack wants (ReturnAddressStack). rst_n=0 on rising edge
 * empties the stack, entries are not cleared.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Stack #(
    parameter  ADDR_WIDTH = 3,                  // 1 << ADDR_WIDTH entries
    parameter  DATA_WIDTH = 8,
    parameter  OVERWRITE  = 0,                  // 1: a push when full overwrites the oldest
    localparam DEPTH      = 1 << ADDR_WIDTH
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  wire                  push,          // ignored when full, unless OVERWRITE=1
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire                  pop,           // ignored when empty
    output wire [DATA_WIDTH-1:0] data_out,      // top entry, valid when empty is 0
    output wire                  empty,
    output wire                  full,
    output logic [ADDR_WIDTH:0]  count          // 0..DEPTH entries
);
    // The entries are a circle: top is the index of the top entry; the entry above it is the
    // next one to write, and when the stack is full it is the oldest, which OVERWRITE
    // replaces.
    logic [DATA_WIDTH-1:0] mem [DEPTH];
    logic [ADDR_WIDTH-1:0] top;
    logic                  replace;     // push and pop of a stack with entries: new top
    logic                  do_push;     // a new entry above the top
    logic                  do_pop;

    assign empty   = count == '0;
    assign full    = count == (ADDR_WIDTH+1)'(DEPTH);
    assign replace = push && pop && !empty;
    assign do_push = push && !replace && (!full || OVERWRITE != 0);
    assign do_pop  = pop && !push && !empty;

    always_ff @(posedge clk)
        if (!rst_n) begin
            top   <= '0;
            count <= '0;
        end else if (do_push) begin
            top <= top + 1'b1;
            if (!full)
                count <= count + 1'b1;
        end else if (do_pop) begin
            top   <= top - 1'b1;
            count <= count - 1'b1;
        end

    always_ff @(posedge clk)
        if (replace)      mem[top]        <= data_in;
        else if (do_push) mem[top + 1'b1] <= data_in;

    assign data_out = mem[top];

endmodule
