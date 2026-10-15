/* Return 1 if input vector has odd number of 1's.
 *
 * Balanced tree of XOR2 cells. Tree nodes are heap-indexed:
 * node 0 is the root, node k has children 2k+1 and 2k+2,
 * nodes WIDTH-1 .. 2*WIDTH-2 are the inputs.
 */
module Parity #(
    parameter WIDTH = 1
)(
   input  wire [WIDTH-1:0] in,
   output wire             parity
);

    genvar k;
    generate
    if (WIDTH == 1) begin: g_wire
        assign parity = in[0];
    end else begin: g_tree
        // split_var: Verilator treats bits separately, no false loop through node.
        wire [2*WIDTH-2:0] node /*verilator split_var*/;
        assign node[2*WIDTH-2:WIDTH-1] = in;
        for (k = 0; k < WIDTH-1; k = k + 1) begin: g_node
            XOR2 u_xor2(.A1(node[2*k+1]), .A2(node[2*k+2]), .Z(node[k]));
        end
        assign parity = node[0];
    end
    endgenerate

endmodule
