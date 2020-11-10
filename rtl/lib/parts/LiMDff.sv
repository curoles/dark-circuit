/* Logic-in-Memory DFF.
 *
 * A smart-memory is a specialized memory block that is customized
 * to perform extra functionalities, such that the output of a smart-memory
 * is not just stored data, but a function of the input and the stored data.
 *
 * Operations:
 * 1. Set new value: do_force=1, do_invert=1|0.
 * 2. Do not change current value: do_force=0, do_nand=do_nxor=0, do_invert=1, in=0.
 * 3. NAND(current,new): do_force=0, do_nand=1, do_nxor=0, do_invert=0.
 * 4.  AND(current,new): do_force=0, do_nand=1, do_nxor=0, do_invert=1.
 * 5. NXOR(current,new): do_force=0, do_nand=0, do_nxor=1, do_invert=0.
 * 6.  XOR(current,new): do_force=0, do_nand=0, do_nxor=1, do_invert=1.
 * 7. NOR (current,new): do_force=0, do_nand=0, do_nxor=0, do_invert=0.
 * 8.  OR (current,new): do_force=0, do_nand=0, do_nxor=0, do_invert=1.
 *
 */
module LiMDff #(
    parameter WIDTH = 1
)(
    input  wire             clk,
    input  wire             do_force,
    input  wire             do_invert, // invert before saving
    //input wire            do_nor, // default operation when both do_nand and do_nxor is 0
    input  wire             do_nand,
    input  wire             do_nxor,
    input  wire [WIDTH-1:0] in,
    output reg  [WIDTH-1:0] out
);

    wire [WIDTH-1:0] new_val, new_val_b4inv, modified_val;
    DFF#(.WIDTH(WIDTH)) dff_(.clk(clk), .in(new_val), .out(out));

    assign new_val_b4inv = (do_force)? in : modified_val;
    assign new_val = (do_inv)? ~new_val_b4inv : new_val_b4inv;

    wire [WIDTH-1:0] nored_val, nanded_val, nxored_val;

    NAND2#(WIDTH) nand_(.in1(in), .in2(out), .out(nanded_val));
    NXOR2#(WIDTH) nxor_(.in1(in), .in2(out), .out(nxored_val));
    NOR2 #(WIDTH) nor_ (.in1(in), .in2(out), .out( nored_val));

    assign modified_val = (do_nand)? nanded_val :
                          (do_nxor)? nxored_val :
                          nored_val;

endmodule
