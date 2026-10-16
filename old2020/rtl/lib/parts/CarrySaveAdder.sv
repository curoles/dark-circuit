module csa 
#(parameter DW = 32 //data-width
)
(
    input logic         [DW-1:0]    in1,
    input logic         [DW-1:0]    in2,
    input logic         [DW-1:0]    in3,
    output logic        [DW-1:0]    ps, //partial sum
    output logic        [DW-1:0]    sc  //shift-carry
);


generate
genvar i;

for (i = 0; i < DW; i++) begin : fa_gen
    FullAdderAOI fulladder_inst (.in1(in1[i]), .in2(in2[i]), .ci(in3[i]), .sum(ps[i]), .co(sc[i]));
end

endgenerate

endmodule

