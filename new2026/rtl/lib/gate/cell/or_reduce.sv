/* OR reduction, returns 1 if any bit of input is 1.
 *
 * Balanced tree of OR2 cells. Tree nodes are heap-indexed:
 * node 0 is the root, node k has children 2k+1 and 2k+2,
 * nodes WIDTH-1 .. 2*WIDTH-2 are the inputs.
 */
module OrReduce #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,
    output wire             out
);

    genvar k;
    generate
    if (WIDTH == 1) begin: g_wire
        assign out = in[0];
    end else begin: g_tree
        wire [2*WIDTH-2:0] node;
        assign node[2*WIDTH-2:WIDTH-1] = in;
        for (k = 0; k < WIDTH-1; k = k + 1) begin: g_node
            OR2 u_or2(.A1(node[2*k+1]), .A2(node[2*k+2]), .Z(node[k]));
        end
        assign out = node[0];
    end
    endgenerate

endmodule
