/* Logic-in-Memory DFF.
 *
 * A smart-memory is a specialized memory block that is customized
 * to perform extra functionalities, such that the output of a smart-memory
 * is not just stored data, but a function of the input and the stored data.
 *
 * Operations:
 * 1. Set new value: do_force=1, do_invert=1|0 (do_invert=1 stores inverted value).
 * 2. Do not change current value: do_force=0, do_nand=do_xnor=0, do_invert=1, in=0.
 * 3. NAND(current,new): do_force=0, do_nand=1, do_xnor=0, do_invert=0.
 * 4.  AND(current,new): do_force=0, do_nand=1, do_xnor=0, do_invert=1.
 * 5. XNOR(current,new): do_force=0, do_nand=0, do_xnor=1, do_invert=0.
 * 6.  XOR(current,new): do_force=0, do_nand=0, do_xnor=1, do_invert=1.
 * 7. NOR (current,new): do_force=0, do_nand=0, do_xnor=0, do_invert=0.
 * 8.  OR (current,new): do_force=0, do_nand=0, do_xnor=0, do_invert=1.
 *
 * Priority: do_force, then do_nand, then do_xnor, otherwise NOR.
 */
module LimDff #(
    parameter WIDTH = 1
)(
    input  wire             clk,
    input  wire             do_force,
    input  wire             do_invert, // invert before saving
    //input wire            do_nor, // default operation when both do_nand and do_xnor is 0
    input  wire             do_nand,
    input  wire             do_xnor,
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);
    wire [WIDTH-1:0] nanded_val, xnored_val, nored_val;
    wire [WIDTH-1:0] xnor_or_nor, modified_val, new_val_b4inv, new_val;

    Nand2 #(WIDTH) u_nand2(.in1(in), .in2(out), .out(nanded_val));
    Xnor2 #(WIDTH) u_xnor2(.in1(in), .in2(out), .out(xnored_val));
    Nor2  #(WIDTH) u_nor2 (.in1(in), .in2(out), .out(nored_val));

    Mux2  #(WIDTH) u_mux2_xnor (.in0(nored_val),    .in1(xnored_val), .sel(do_xnor),  .out(xnor_or_nor));
    Mux2  #(WIDTH) u_mux2_nand (.in0(xnor_or_nor),  .in1(nanded_val), .sel(do_nand),  .out(modified_val));
    Mux2  #(WIDTH) u_mux2_force(.in0(modified_val), .in1(in),         .sel(do_force), .out(new_val_b4inv));

    // XOR with 1 inverts, XOR with 0 passes value.
    Xor2  #(WIDTH) u_xor2_inv(.in1(new_val_b4inv), .in2({WIDTH{do_invert}}), .out(new_val));

    Dff   #(WIDTH) u_dff(.clk(clk), .in(new_val), .out(out));

endmodule
