interface JtagBfm;

    bit tck, trst, tdi, tms, tdo;

    initial begin
        tck = 0;
        forever begin
            #10;
            tck = ~tck;
        end
    end

    initial begin
        trst = 0;
        #10;
        trst = 1;
        #50;
        trst = 0;
    end

endinterface: JtagBfm
