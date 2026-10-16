/* Exhaustive test of Decoder block, behave or struct version,
 * with SIZE 1, 3 and 5 side by side.
 *
 * Stops at the first mismatch with $fatal.
 */
module TbDecoder;
    reg         en;
    reg  [4:0]  v;
    wire [1:0]  out1;
    wire [7:0]  out3;
    wire [31:0] out5;
    integer i;

    Decoder #(.SIZE(1)) u_decoder_1(.in(v[0]),   .en(en), .out(out1));
    Decoder #(.SIZE(3)) u_decoder_3(.in(v[2:0]), .en(en), .out(out3));
    Decoder #(.SIZE(5)) u_decoder_5(.in(v),      .en(en), .out(out5));

    initial begin
        for (i = 0; i < 2**6; i = i + 1) begin
            {en, v} = i[5:0];
            #1;
            if (out1 !== (en ? (2'd1 << v[0]) : 2'd0))
                $fatal(1, "Decoder SIZE=1: in=%b en=%b got out=%b", v[0], en, out1);
            if (out3 !== (en ? (8'd1 << v[2:0]) : 8'd0))
                $fatal(1, "Decoder SIZE=3: in=%b en=%b got out=%b", v[2:0], en, out3);
            if (out5 !== (en ? (32'd1 << v) : 32'd0))
                $fatal(1, "Decoder SIZE=5: in=%b en=%b got out=%b", v, en, out5);
        end
        $display("PASS");
        $finish;
    end
endmodule
