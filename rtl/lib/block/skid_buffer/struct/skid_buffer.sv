/* Skid buffer: valid/ready register stage, made of gates.
 *
 * Items from channel in come out of channel out one cycle later, one item per cycle at
 * full speed. out_valid and out_data come from the output register, in_ready from the
 * skid register: all outputs are flip-flops, so the buffer cuts combinational paths in
 * both directions (valid/ready rules in AGENTS.md). When out stalls (out_valid=1,
 * out_ready=0) an item that arrives in the same cycle goes into the skid register and
 * in_ready becomes 0; the skid item moves to the output register when out takes the
 * waiting one. rst_n=0 empties both registers; data registers are not reset.
 *
 * stall = out_valid and not out_ready, any = skid_valid or in_valid (an item waits):
 * out_valid <= stall or any, skid_valid <= stall and any. The next item for out is the
 * skid item when there is one, else in_data; it is also the next skid data, because
 * the skid register loads in_data while empty (nobody reads it until skid_valid=1).
 */
module SkidBuffer #(
    parameter DATA_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,       // synchronous reset, active low: empty

    input  wire                  in_valid,    // channel in
    output wire                  in_ready,
    input  wire [DATA_WIDTH-1:0] in_data,

    output wire                  out_valid,   // channel out
    input  wire                  out_ready,
    output wire [DATA_WIDTH-1:0] out_data
);
    wire                  not_out_ready;
    wire                  stall;              // out holds an item that is not taken
    wire                  out_free;
    wire                  any;                // an item is waiting: in the skid register or at in
    wire                  out_valid_d;
    wire                  skid_valid_d;
    wire                  skid_valid;
    wire [DATA_WIDTH-1:0] skid_data;
    wire [DATA_WIDTH-1:0] next_item;          // skid item when there is one, else in_data
    wire [DATA_WIDTH-1:0] out_data_d;

    Inv  #(1) u_inv_out_ready  (.in(out_ready), .out(not_out_ready));
    And2 #(1) u_and2_stall     (.in1(out_valid), .in2(not_out_ready), .out(stall));
    Inv  #(1) u_inv_stall      (.in(stall), .out(out_free));
    Or2  #(1) u_or2_any        (.in1(skid_valid), .in2(in_valid), .out(any));
    Or2  #(1) u_or2_out_valid  (.in1(stall), .in2(any), .out(out_valid_d));
    And2 #(1) u_and2_skid_valid(.in1(stall), .in2(any), .out(skid_valid_d));
    Inv  #(1) u_inv_skid_valid (.in(skid_valid), .out(in_ready));

    DffSyncRst #(1) u_dff_sync_rst_out_valid (.clk, .rst_n, .in(out_valid_d),  .out(out_valid));
    DffSyncRst #(1) u_dff_sync_rst_skid_valid(.clk, .rst_n, .in(skid_valid_d), .out(skid_valid));

    Mux2 #(DATA_WIDTH) u_mux2_next_item(.in0(in_data), .in1(skid_data), .sel(skid_valid), .out(next_item));
    Dff  #(DATA_WIDTH) u_dff_skid_data (.clk, .in(next_item), .out(skid_data));
    Mux2 #(DATA_WIDTH) u_mux2_out_data (.in0(out_data), .in1(next_item), .sel(out_free), .out(out_data_d));
    Dff  #(DATA_WIDTH) u_dff_out_data  (.clk, .in(out_data_d), .out(out_data));

endmodule
