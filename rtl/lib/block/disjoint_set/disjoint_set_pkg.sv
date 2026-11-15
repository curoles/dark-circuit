/* Disjoint set (union-find): the operations of DisjointSet and DisjointSetT.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package DisjointSetPkg;

    typedef enum logic [1:0] {
        DS_FIND  = 2'd0,                // the root of a's group and the group's payload
        DS_UNION = 2'd1,                // a's and b's groups become one, payloads merged
        DS_SET   = 2'd2,                // the payload of a's group := payload
        DS_CLEAR = 2'd3                 // every item its own group, every payload 0
    } ds_op_e;

endpackage
