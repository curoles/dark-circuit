interface JtagBfm;

    bit tck, trst, tdi, tms, tdo;

    initial begin
        tck = 0;
        forever begin
            #1;
            tck = ~tck;
        end
    end

    initial begin
        trst = 0;
        #1;
        trst = 1;
        #5;
        trst = 0;
    end

endinterface: JtagBfm
