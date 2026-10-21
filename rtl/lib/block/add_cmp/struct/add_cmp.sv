/* Adder-comparator: eq = (a + b == c), mod 2^WIDTH, made of parts and gates.
 *
 * a + b wraps around like a WIDTH-bit adder, its carry out is not compared.
 *
 * No carry chain, see The Power of Carry-Save Addition, D. R. Lutz 1994:
 * a + b == c  <=>  a + b - c == 0  <=>  a + b + ~c + 1 == 0  <=>  a + b + ~c == all ones.
 * Carry save adder makes a + b + ~c = ps + (sc << 1) without carry chain, and
 * X + Y == all ones exactly when X == ~Y (mod 2^WIDTH, X = -1 - Y = ~Y),
 * so eq is AND of all bits of ps ^ (sc << 1). Delay is full adder, XOR and AND tree,
 * it does not grow with a carry chain like a + b would.
 *
 * @author    Igor Lesik
 * @copyright 2019 Igor Lesik, MIT License
 */
module AddCmp #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire [WIDTH-1:0] c,
    output wire             eq   // a + b == c
);
    wire [WIDTH-1:0] c_inv, ps, sc, t;
    // sc << 1; the top carry has weight 2^WIDTH and is not compared.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [WIDTH:0]   sc_shift;
    /* verilator lint_on UNUSEDSIGNAL */

    Inv            #(WIDTH)         u_inv             (.in(c), .out(c_inv));
    CarrySaveAdder #(.WIDTH(WIDTH)) u_carry_save_adder(.in1(a), .in2(b), .in3(c_inv), .ps(ps), .sc(sc));
    assign sc_shift = {sc, 1'b0};
    Xor2           #(WIDTH)         u_xor2            (.in1(ps), .in2(sc_shift[WIDTH-1:0]), .out(t));
    AndReduce      #(WIDTH)         u_and_reduce      (.in(t), .out(eq));

endmodule
