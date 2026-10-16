/* Up/down counter with synchronous reset and load, behavioral.
 *
 * Priority: rst_n=0 resets, then load, then count_en counts.
 * Counting up co is carry; counting down co=1 is borrow, 0 wraps to all ones.
 * co keeps its value while counter holds.
 */
module Counter #(
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst_n,    // synchronous reset, active low
    input  wire             load,     // synchronous load of in
    input  wire [WIDTH-1:0] in,
    input  wire             up_down,  // 1 counts up, 0 counts down
    input  wire             count_en,
    output reg  [WIDTH-1:0] out,
    output reg              co        // carry (up) or borrow (down)
);
    localparam [WIDTH:0] ONE = {{WIDTH{1'b0}}, 1'b1};

    always_ff @(posedge clk)
        if (!rst_n)
            {co, out} <= {(WIDTH+1){1'b0}};
        else if (load)
            {co, out} <= {1'b0, in};
        else if (count_en)
            {co, out} <= up_down ? {1'b0, out} + ONE : {1'b0, out} - ONE;

endmodule
