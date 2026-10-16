/*
 *
 *
 */
module Counter #(
    parameter WIDTH=8
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             load,
    input  wire [WIDTH-1:0] in,
    input  wire             up_down,
    input  wire             count_en,
    output reg  [WIDTH-1:0] out,
    output reg              co
);

    localparam WIDTH_WITH_CARRY = WIDTH + 1;

    always @(posedge clk)
    begin
        if (!rst_n) begin         // sync reset
            {co,out} <= {WIDTH_WITH_CARRY{1'b0}};
        end else if (load) begin  // sync load
            {co,out} <= in;
        end else if (count_en) begin // sync increment/decrement
            if (up_down)
                {co,out} <= out + 1'b1;
            else
                {co,out} <= out - 1'b1;
        end
    end

endmodule

