/* Disjoint set of payload type T: DisjointSet with PAYLOAD_WIDTH = $bits(T). The payload is
 * the user's struct (a size, an odd count, a flag, ...), never looked inside; merge is the
 * user's function of merge_a and merge_b. Whichever DisjointSet the flist has.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module DisjointSetT import DisjointSetPkg::*; #(
    parameter      N  = 16,                         // items, 2 or more
    parameter type T  = logic [7:0],                // type of a group's payload
    localparam     IW = $clog2(N)                   // bits of an item
)(
    input  wire          clk,
    input  wire          rst_n,                     // synchronous reset, active low
    input  wire          req_valid,                 // channel req: an operation
    output wire          req_ready,
    input  ds_op_e       req_op,
    input  wire [IW-1:0] req_a,
    input  wire [IW-1:0] req_b,                     // DS_UNION
    input  T             req_payload,               // DS_SET
    output wire          rsp_valid,                 // channel rsp: its answer
    input  wire          rsp_ready,
    output wire [IW-1:0] rsp_root,                  // the root of the group
    output T             rsp_payload,               // the group's payload
    output wire          rsp_same,                  // DS_UNION: a and b were in one group
    output T             merge_a,                   // a union's link: the payload of a's group
    output T             merge_b,                   // the payload of b's group
    input  T             merge                      // the merged payload, from the user
);
    DisjointSet #(.N(N), .PAYLOAD_WIDTH($bits(T))) u_disjoint_set(
        .clk, .rst_n, .req_valid, .req_ready, .req_op, .req_a, .req_b, .req_payload,
        .rsp_valid, .rsp_ready, .rsp_root, .rsp_payload, .rsp_same, .merge_a, .merge_b,
        .merge);

endmodule
