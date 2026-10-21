/* NOR reduction, returns 1 if all bits of input are 0.
 *
 * Balanced tree of OR2 cells followed by INV. Tree nodes are heap-indexed:
 * node 0 is the root, node k has children 2k+1 and 2k+2,
 * nodes WIDTH-1 .. 2*WIDTH-2 are the inputs.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module NorReduce #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,
    output wire             out
);

    genvar k;
    generate
    if (WIDTH == 1) begin: g_inv
        INV u_inv(.I(in[0]), .ZN(out));
    end else begin: g_tree
        // split_var: Verilator treats bits separately, no false loop through node.
        wire [2*WIDTH-2:0] node /*verilator split_var*/;
        assign node[2*WIDTH-2:WIDTH-1] = in;
        for (k = 0; k < WIDTH-1; k = k + 1) begin: g_node
            OR2 u_or2(.A1(node[2*k+1]), .A2(node[2*k+2]), .Z(node[k]));
        end
        INV u_inv(.I(node[0]), .ZN(out));
    end
    endgenerate

endmodule
