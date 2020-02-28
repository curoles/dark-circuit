// =================================================================================================
// =                                                                                               =
// = This document is protected by copyright and other related rights and the practice or          =
// = implementation of the information contained in this document may be protected by one or more  =
// = patents or pending patent applications. No part of this document may be reproduced in any     =
// = form and by any means without the express prior written permission of Tachyum.                =
// =                                                                                               =
// =                                 COPYRIGHT (C) 2019 Dark Circuit                               =
// =                                                                                               =
// =================================================================================================
//
//       |         |         |         |         |         |         |         |         |         |
//      10        20        30        40        50        60        70        80        90       100
// 4567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890

module AddCmp50 (
    input  wire [50-1:0] a,
    input  wire [50-1:0] b,
    input  wire [50-1:0] c,
    output wire          eq
);

wire [50-1:0] s;
wire [50  :0] cy;
wire [50-1:0] t;
wire group0;
wire group1;
wire group2;
wire group3;
wire group4;
wire group5;
wire group6;
wire group7;
wire group8;
wire group9;
wire group10;
wire group11;
wire group12;

assign cy[0] = 0;

FullAdder u_fa0(.in1(a[0]), .in2(b[0]), .ci(~c[0]), .sum(s[0]), .co(cy[1]));
FullAdder u_fa1(.in1(a[1]), .in2(b[1]), .ci(~c[1]), .sum(s[1]), .co(cy[2]));
FullAdder u_fa2(.in1(a[2]), .in2(b[2]), .ci(~c[2]), .sum(s[2]), .co(cy[3]));
FullAdder u_fa3(.in1(a[3]), .in2(b[3]), .ci(~c[3]), .sum(s[3]), .co(cy[4]));
FullAdder u_fa4(.in1(a[4]), .in2(b[4]), .ci(~c[4]), .sum(s[4]), .co(cy[5]));
FullAdder u_fa5(.in1(a[5]), .in2(b[5]), .ci(~c[5]), .sum(s[5]), .co(cy[6]));
FullAdder u_fa6(.in1(a[6]), .in2(b[6]), .ci(~c[6]), .sum(s[6]), .co(cy[7]));
FullAdder u_fa7(.in1(a[7]), .in2(b[7]), .ci(~c[7]), .sum(s[7]), .co(cy[8]));
FullAdder u_fa8(.in1(a[8]), .in2(b[8]), .ci(~c[8]), .sum(s[8]), .co(cy[9]));
FullAdder u_fa9(.in1(a[9]), .in2(b[9]), .ci(~c[9]), .sum(s[9]), .co(cy[10]));
FullAdder u_fa10(.in1(a[10]), .in2(b[10]), .ci(~c[10]), .sum(s[10]), .co(cy[11]));
FullAdder u_fa11(.in1(a[11]), .in2(b[11]), .ci(~c[11]), .sum(s[11]), .co(cy[12]));
FullAdder u_fa12(.in1(a[12]), .in2(b[12]), .ci(~c[12]), .sum(s[12]), .co(cy[13]));
FullAdder u_fa13(.in1(a[13]), .in2(b[13]), .ci(~c[13]), .sum(s[13]), .co(cy[14]));
FullAdder u_fa14(.in1(a[14]), .in2(b[14]), .ci(~c[14]), .sum(s[14]), .co(cy[15]));
FullAdder u_fa15(.in1(a[15]), .in2(b[15]), .ci(~c[15]), .sum(s[15]), .co(cy[16]));
FullAdder u_fa16(.in1(a[16]), .in2(b[16]), .ci(~c[16]), .sum(s[16]), .co(cy[17]));
FullAdder u_fa17(.in1(a[17]), .in2(b[17]), .ci(~c[17]), .sum(s[17]), .co(cy[18]));
FullAdder u_fa18(.in1(a[18]), .in2(b[18]), .ci(~c[18]), .sum(s[18]), .co(cy[19]));
FullAdder u_fa19(.in1(a[19]), .in2(b[19]), .ci(~c[19]), .sum(s[19]), .co(cy[20]));
FullAdder u_fa20(.in1(a[20]), .in2(b[20]), .ci(~c[20]), .sum(s[20]), .co(cy[21]));
FullAdder u_fa21(.in1(a[21]), .in2(b[21]), .ci(~c[21]), .sum(s[21]), .co(cy[22]));
FullAdder u_fa22(.in1(a[22]), .in2(b[22]), .ci(~c[22]), .sum(s[22]), .co(cy[23]));
FullAdder u_fa23(.in1(a[23]), .in2(b[23]), .ci(~c[23]), .sum(s[23]), .co(cy[24]));
FullAdder u_fa24(.in1(a[24]), .in2(b[24]), .ci(~c[24]), .sum(s[24]), .co(cy[25]));
FullAdder u_fa25(.in1(a[25]), .in2(b[25]), .ci(~c[25]), .sum(s[25]), .co(cy[26]));
FullAdder u_fa26(.in1(a[26]), .in2(b[26]), .ci(~c[26]), .sum(s[26]), .co(cy[27]));
FullAdder u_fa27(.in1(a[27]), .in2(b[27]), .ci(~c[27]), .sum(s[27]), .co(cy[28]));
FullAdder u_fa28(.in1(a[28]), .in2(b[28]), .ci(~c[28]), .sum(s[28]), .co(cy[29]));
FullAdder u_fa29(.in1(a[29]), .in2(b[29]), .ci(~c[29]), .sum(s[29]), .co(cy[30]));
FullAdder u_fa30(.in1(a[30]), .in2(b[30]), .ci(~c[30]), .sum(s[30]), .co(cy[31]));
FullAdder u_fa31(.in1(a[31]), .in2(b[31]), .ci(~c[31]), .sum(s[31]), .co(cy[32]));
FullAdder u_fa32(.in1(a[32]), .in2(b[32]), .ci(~c[32]), .sum(s[32]), .co(cy[33]));
FullAdder u_fa33(.in1(a[33]), .in2(b[33]), .ci(~c[33]), .sum(s[33]), .co(cy[34]));
FullAdder u_fa34(.in1(a[34]), .in2(b[34]), .ci(~c[34]), .sum(s[34]), .co(cy[35]));
FullAdder u_fa35(.in1(a[35]), .in2(b[35]), .ci(~c[35]), .sum(s[35]), .co(cy[36]));
FullAdder u_fa36(.in1(a[36]), .in2(b[36]), .ci(~c[36]), .sum(s[36]), .co(cy[37]));
FullAdder u_fa37(.in1(a[37]), .in2(b[37]), .ci(~c[37]), .sum(s[37]), .co(cy[38]));
FullAdder u_fa38(.in1(a[38]), .in2(b[38]), .ci(~c[38]), .sum(s[38]), .co(cy[39]));
FullAdder u_fa39(.in1(a[39]), .in2(b[39]), .ci(~c[39]), .sum(s[39]), .co(cy[40]));
FullAdder u_fa40(.in1(a[40]), .in2(b[40]), .ci(~c[40]), .sum(s[40]), .co(cy[41]));
FullAdder u_fa41(.in1(a[41]), .in2(b[41]), .ci(~c[41]), .sum(s[41]), .co(cy[42]));
FullAdder u_fa42(.in1(a[42]), .in2(b[42]), .ci(~c[42]), .sum(s[42]), .co(cy[43]));
FullAdder u_fa43(.in1(a[43]), .in2(b[43]), .ci(~c[43]), .sum(s[43]), .co(cy[44]));
FullAdder u_fa44(.in1(a[44]), .in2(b[44]), .ci(~c[44]), .sum(s[44]), .co(cy[45]));
FullAdder u_fa45(.in1(a[45]), .in2(b[45]), .ci(~c[45]), .sum(s[45]), .co(cy[46]));
FullAdder u_fa46(.in1(a[46]), .in2(b[46]), .ci(~c[46]), .sum(s[46]), .co(cy[47]));
FullAdder u_fa47(.in1(a[47]), .in2(b[47]), .ci(~c[47]), .sum(s[47]), .co(cy[48]));
FullAdder u_fa48(.in1(a[48]), .in2(b[48]), .ci(~c[48]), .sum(s[48]), .co(cy[49]));
FullAdder u_fa49(.in1(a[49]), .in2(b[49]), .ci(~c[49]), .sum(s[49]), .co(cy[50]));

assign t[0] = cy[0] ^ s[0];
assign t[1] = cy[1] ^ s[1];
assign t[2] = cy[2] ^ s[2];
assign t[3] = cy[3] ^ s[3];
assign t[4] = cy[4] ^ s[4];
assign t[5] = cy[5] ^ s[5];
assign t[6] = cy[6] ^ s[6];
assign t[7] = cy[7] ^ s[7];
assign t[8] = cy[8] ^ s[8];
assign t[9] = cy[9] ^ s[9];
assign t[10] = cy[10] ^ s[10];
assign t[11] = cy[11] ^ s[11];
assign t[12] = cy[12] ^ s[12];
assign t[13] = cy[13] ^ s[13];
assign t[14] = cy[14] ^ s[14];
assign t[15] = cy[15] ^ s[15];
assign t[16] = cy[16] ^ s[16];
assign t[17] = cy[17] ^ s[17];
assign t[18] = cy[18] ^ s[18];
assign t[19] = cy[19] ^ s[19];
assign t[20] = cy[20] ^ s[20];
assign t[21] = cy[21] ^ s[21];
assign t[22] = cy[22] ^ s[22];
assign t[23] = cy[23] ^ s[23];
assign t[24] = cy[24] ^ s[24];
assign t[25] = cy[25] ^ s[25];
assign t[26] = cy[26] ^ s[26];
assign t[27] = cy[27] ^ s[27];
assign t[28] = cy[28] ^ s[28];
assign t[29] = cy[29] ^ s[29];
assign t[30] = cy[30] ^ s[30];
assign t[31] = cy[31] ^ s[31];
assign t[32] = cy[32] ^ s[32];
assign t[33] = cy[33] ^ s[33];
assign t[34] = cy[34] ^ s[34];
assign t[35] = cy[35] ^ s[35];
assign t[36] = cy[36] ^ s[36];
assign t[37] = cy[37] ^ s[37];
assign t[38] = cy[38] ^ s[38];
assign t[39] = cy[39] ^ s[39];
assign t[40] = cy[40] ^ s[40];
assign t[41] = cy[41] ^ s[41];
assign t[42] = cy[42] ^ s[42];
assign t[43] = cy[43] ^ s[43];
assign t[44] = cy[44] ^ s[44];
assign t[45] = cy[45] ^ s[45];
assign t[46] = cy[46] ^ s[46];
assign t[47] = cy[47] ^ s[47];
assign t[48] = cy[48] ^ s[48];
assign t[49] = cy[49] ^ s[49];

assign group0 = ~(t[0] & t[1] & t[2] & t[3]);
assign group1 = ~(t[4] & t[5] & t[6] & t[7]);
assign group2 = ~(t[8] & t[9] & t[10] & t[11]);
assign group3 = ~(t[12] & t[13] & t[14] & t[15]);
assign group4 = ~(t[16] & t[17] & t[18] & t[19]);
assign group5 = ~(t[20] & t[21] & t[22] & t[23]);
assign group6 = ~(t[24] & t[25] & t[26] & t[27]);
assign group7 = ~(t[28] & t[29] & t[30] & t[31]);
assign group8 = ~(t[32] & t[33] & t[34] & t[35]);
assign group9 = ~(t[36] & t[37] & t[38] & t[39]);
assign group10 = ~(t[40] & t[41] & t[42] & t[43]);
assign group11 = ~(t[44] & t[45] & t[46] & t[47]);
assign group12 = ~(t[48] & t[49]);

assign eq = ~(group0 | group1 | group2 | group3 | group4 | group5 | group6 | group7 | group8 | group9 | group10 | group11 | group12);

endmodule
