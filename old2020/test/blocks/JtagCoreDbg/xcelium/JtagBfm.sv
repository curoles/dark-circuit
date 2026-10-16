interface JtagBfm;

    bit tck, trst, tdi, tms, tdo;

    initial begin
        tck = 0;
        forever begin
            #10;
            tck = ~tck;
        end
    end

    /*initial begin
        trst = 0;
        #10;
        trst = 1;
        #50;
        trst = 0;
    end*/

    task tick(input bit [1:0] tdi_tms);
        tdi = tdi_tms[0];
        tms = tdi_tms[1];
        @(posedge tck);
        //$display("%t TDI:%b TMS:%b", $time, tdi, tms);
    endtask: tick

    task tick4(input bit [1:0] b1, b2, b3, b4);
        tick(b1); tick(b2); tick(b3); tick(b4);
    endtask

    task tick5(input bit [1:0] b1, b2, b3, b4, b5);
        tick(b1); tick(b2); tick(b3); tick(b4); tick(b5);
    endtask: tick5

    task tick8(input bit [1:0] b1, b2, b3, b4, b5, b6, b7, b8);
        tick(b1); tick(b2); tick(b3); tick(b4);
        tick(b5); tick(b6); tick(b7); tick(b8);
    endtask: tick8

    task go_shift_ir();
        tick5(2'b00,2'b10,2'b10,2'b00,2'b00);
    endtask

    task go_shift_dr();
        tick4(2'b00,2'b10,2'b00,2'b00);
    endtask

    task go_idle_to_shift_dr();
        tick4(2'b00,2'b10,2'b00,2'b00);
    endtask

    task go_exit1_to_update_dr();
        tick(2'b10);
    endtask

    task go_exit_ir_to_idle();
        tick(2'b10); tick(2'b00);
    endtask

    task go_capture_dr();
        tick(2'b00); tick(2'b10); tick(2'b00);
    endtask

    task do_ir_idcode();
        tick8(2'b00,2'b01,2'b00,2'b00,2'b00,2'b00,2'b00,2'b10);
    endtask

    task do_ir_bypass();
        tick8(2'b01,2'b01,2'b01,2'b01,2'b01,2'b01,2'b01,2'b11);
    endtask

    //CDPACC = 8'b0000_0101;
    task do_ir_cdpacc();
        tick8(2'b01,2'b00,2'b01,2'b00,2'b00,2'b00,2'b00,2'b10);
    endtask

    task do_reset_5tms();
        tick5(2'b10,2'b10,2'b10,2'b10,2'b10);
    endtask

    task do_shiftin_int32(input bit [31:0] d);
        for (integer i = 0; i < 32; i++) begin
            //$display("%t JTAG shiftin %b", $time, d[i]);
            if (i==31) tick({1'b1, d[i]}); else tick({1'b0, d[i]});
        end
    endtask

endinterface: JtagBfm
