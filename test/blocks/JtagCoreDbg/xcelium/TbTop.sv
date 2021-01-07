module TbTop (

);
    wire tck;   // test clock
    wire trst;  // test reset
    wire tdi;   // test Data In
    wire tms;   // test Mode Select
    wire tdo;    // test Data Out

    DbgAccPort _dap(
        .tck(tck),
        .trst(trst),
        .tdi(tdi),
        .tms(tms),
        .tdo(tdo)
    );

endmodule: TbTop
