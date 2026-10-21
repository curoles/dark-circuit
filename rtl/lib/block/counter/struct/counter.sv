/* Up/down counter with synchronous reset and load, made of parts and gates.
 *
 * Priority: rst_n=0 resets, then load, then count_en counts.
 * Counting up co is carry; counting down co=1 is borrow, 0 wraps to all ones.
 * co keeps its value while counter holds.
 *
 * out + 1 = RippleCarryAdder(out, 0, ci=1), its carry is co.
 * out - 1 = RippleCarryAdder(out, all ones, ci=0), inverted carry is borrow.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
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
    output wire [WIDTH-1:0] out,
    output wire             co        // carry (up) or borrow (down)
);
    wire [WIDTH-1:0] inc, dec;
    wire             inc_co, dec_co, dec_borrow;
    wire [WIDTH:0]   step_val, count_val, next_val;

    RippleCarryAdder #(.WIDTH(WIDTH)) u_ripple_carry_adder_inc(
        .in1(out), .in2({WIDTH{1'b0}}), .ci(1'b1), .co(inc_co), .sum(inc));
    RippleCarryAdder #(.WIDTH(WIDTH)) u_ripple_carry_adder_dec(
        .in1(out), .in2({WIDTH{1'b1}}), .ci(1'b0), .co(dec_co), .sum(dec));
    Inv #(1) u_inv_borrow(.in(dec_co), .out(dec_borrow));

    Mux2 #(WIDTH+1) u_mux2_up_down (.in0({dec_borrow, dec}), .in1({inc_co, inc}), .sel(up_down),  .out(step_val));
    Mux2 #(WIDTH+1) u_mux2_count_en(.in0({co, out}),         .in1(step_val),      .sel(count_en), .out(count_val));
    Mux2 #(WIDTH+1) u_mux2_load    (.in0(count_val),         .in1({1'b0, in}),    .sel(load),     .out(next_val));

    DffSyncRst #(WIDTH+1) u_dff_sync_rst(.clk(clk), .rst_n(rst_n), .in(next_val), .out({co, out}));

endmodule
