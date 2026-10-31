/* Configuration of the NoC of a design: its numbers, and its flit built from them with the
 * library's macros (later generated from YAML, as Mig2ConfigPkg is).
 */
`include "../block/noc/dark_circuit_noc.svh"

package NocConfigPkg;

    localparam NUM_VCS    = 4;      // virtual channels on every link
    localparam X_WIDTH    = 2;      // mesh up to 4 x 4
    localparam Y_WIDTH    = 2;
    localparam DATA_WIDTH = 32;     // data of a flit
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS);

    typedef `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH) flit_t;
    typedef `DC_NOC_HEAD_T(X_WIDTH, Y_WIDTH, DATA_WIDTH) head_t;

endpackage
