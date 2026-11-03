/* Flow-through buffer: a valid/ready stage of one entry that cuts the ready path only, made
 * of gates.
 *
 * Same ports, parameter and behavior as the behave version (see there):
 *   in_ready  = Inv(full)                     out_valid = Or2(full, in_valid)
 *   out_data  = Mux2(in_data, entry, full)    full = DffSyncRst(And2(out_valid, Inv(out_ready)))
 *   entry     = DffEn (en: in_ready) of in_data
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module FlowThroughBuffer #(
    parameter DATA_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,       // synchronous reset, active low: empty

    input  wire                  in_valid,    // channel in
    output wire                  in_ready,    // the entry is empty: a flip-flop
    input  wire [DATA_WIDTH-1:0] in_data,

    output wire                  out_valid,   // channel out
    input  wire                  out_ready,
    output wire [DATA_WIDTH-1:0] out_data
);
    wire                  full;               // the entry holds an item out did not take
    wire                  full_next;
    wire                  out_ready_n;
    wire [DATA_WIDTH-1:0] entry;

    // @kb: rtl/lib/block/flow_through_buffer/design
    Inv  #(1)          u_inv_in_ready (.in(full), .out(in_ready));
    Or2  #(1)          u_or2_out_valid(.in1(full), .in2(in_valid), .out(out_valid));
    Mux2 #(DATA_WIDTH) u_mux2_out_data(.in0(in_data), .in1(entry), .sel(full), .out(out_data));

    Inv  #(1) u_inv_out_ready(.in(out_ready), .out(out_ready_n));
    And2 #(1) u_and2_full    (.in1(out_valid), .in2(out_ready_n), .out(full_next));
    DffSyncRst #(1) u_dff_sync_rst_full(.clk, .rst_n, .in(full_next), .out(full));

    DffEn #(DATA_WIDTH) u_dff_en_entry(.clk, .en(in_ready), .in(in_data), .out(entry));

endmodule
