module TbTop (

);

    localparam WIDTH = 64;
    localparam CMD_WIDTH = ALU1_CMD_WIDTH;

    Alu1Bfm#(WIDTH) bfm();

    Alu1#(.WIDTH(WIDTH))
        alu_(.cmd(bfm.alu_cmd), .in1(bfm.alu_in1), .in2(bfm.alu_in2),
        .co(bfm.alu_co), .out(bfm.alu_out));

    Tester#(WIDTH)     tester_(bfm);
    Scoreboard#(WIDTH) scoreboard_(bfm);
    Coverage#(WIDTH)   coverage_(bfm);

endmodule: TbTop
