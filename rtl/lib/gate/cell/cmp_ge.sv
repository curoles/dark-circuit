/* Comparator, returns 1 if in1 is greater than or equal to in2, both unsigned.
 *
 * A tree of log2(WIDTH) levels, not a chain: WIDTH is padded to P, a power of 2 (the
 * padding bits equal). Per bit gt = in1 & ~in2 (Inv, And2) and eq = Xnor2. A node of a
 * higher part h and a lower part l gives gt = gt_h | (eq_h & gt_l) (Ao21) and
 * eq = eq_h & eq_l (And2); at the root ge = gt | eq (Or2). Nodes are heap-indexed, as in
 * AndReduce: node 0 is the root, node n has children 2n+1 (the lower part) and 2n+2 (the
 * higher), nodes P-1 .. 2P-2 are bits 0 .. P-1 (the tree is perfect, so a node's leaves are
 * a run of bits, its lower child's below its higher child's).
 *
 *   bit:    gt = in1 & ~in2, eq = ~(in1 ^ in2)
 *   node:   gt = gt_h | (eq_h & gt_l)        eq = eq_h & eq_l
 *   root:   ge = gt | eq                     (one bit: ge = in1 | ~in2)
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module CmpGe #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire             ge
);
    localparam P = 1 << ((WIDTH > 1) ? $clog2(WIDTH) : 0);  // bits of the tree

    wire [WIDTH-1:0] in2_n;

    Inv #(WIDTH) u_inv(.in(in2), .out(in2_n));

    if (WIDTH == 1) begin: g_bit
        Or2 #(1) u_or2(.in1(in1), .in2(in2_n), .out(ge));
    end else begin: g_tree
        // split_var: Verilator treats bits separately, no false loop through the nodes.
        wire [2*P-2:0] gt /*verilator split_var*/;     // in1 > in2 on the node's bits
        wire [2*P-2:0] eq /*verilator split_var*/;     // in1 == in2 on the node's bits

        And2  #(WIDTH) u_and2 (.in1(in1), .in2(in2_n), .out(gt[P-1 +: WIDTH]));
        Xnor2 #(WIDTH) u_xnor2(.in1(in1), .in2(in2), .out(eq[P-1 +: WIDTH]));
        if (P > WIDTH) begin: g_pad
            assign gt[P-1+WIDTH +: P-WIDTH] = '0;
            assign eq[P-1+WIDTH +: P-WIDTH] = '1;
        end

        for (genvar n = 0; n < P - 1; n++) begin: g_node
            Ao21 #(1) u_ao21(.in1(eq[2*n+2]), .in2(gt[2*n+1]), .in3(gt[2*n+2]), .out(gt[n]));
            And2 #(1) u_and2(.in1(eq[2*n+2]), .in2(eq[2*n+1]), .out(eq[n]));
        end

        Or2 #(1) u_or2(.in1(gt[0]), .in2(eq[0]), .out(ge));
    end

endmodule
