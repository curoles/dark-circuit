class TestApbWrite extends uvm_test;

    `uvm_component_utils(TestApbWrite)

    Env _env;
    virtual JtagBfm _jtag;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    function void build_phase(uvm_phase phase);
        Tester::type_id::set_type_override(Tester::get_type());
        _env = Env::type_id::create("_env", this);
        if(!uvm_config_db #(virtual JtagBfm)::get(null, "*", "_jtag_bfm", _jtag))
            $fatal(1, "Failed to get JTAG BFM");
    endfunction: build_phase

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        _jtag.trst = 1'b0;
        #1;
        _jtag.trst = 1'b1;
        repeat(5) @(posedge _jtag.tck);
        _jtag.trst = 1'b0;

        $display("%t Set state=Shift-IR", $time);
        _jtag.go_shift_ir();
        $display("%t Set IR=CDPACC", $time);
        _jtag.do_ir_cdpacc();

        _jtag.go_exit_ir_to_idle();

        // Set state=Shift-DR and shift in 36 bits of data, reg addr
        $display("%t Set state=Shift-DR", $time);
        _jtag.go_idle_to_shift_dr();

        $display("%t shift-in TADDR+W", $time);
        _jtag.tick4(2'b01, 2'b01, 2'b00, 2'b00); // [0] 1=W [3:1] 001==TADDR
        $display("%t shift-in TADDR val", $time);
        _jtag.do_shiftin_int32(32'h2);

        // Trigger APB transaction
        $display("%t Set state=Update-DR", $time);
        _jtag.go_exit1_to_update_dr();

        // Set state=Shift-DR and shift in 36 bits of data, reg data
        $display("%t Set state=Shift-DR", $time);
        _jtag.tick(2'b10); _jtag.tick(2'b00); _jtag.tick(2'b00);

        $display("%t shift-in TDR+W", $time);
        _jtag.tick4(2'b01, 2'b00, 2'b01, 2'b00); // [0] 1=W [3:1] 010==DTR
        $display("%t shift-in TDR val", $time);
        _jtag.do_shiftin_int32(32'h55555555);

        // Trigger APB transaction
        $display("%t Set state=Update-DR, trigger APB transaction", $time);
        _jtag.go_exit1_to_update_dr();

        // Read reply
        $display("%t Set state=Capture-DR", $time);
        _jtag.tick(2'b10); _jtag.tick(2'b00);

        // Shift reply out
        $display("%t Set state=Shift-DR", $time);
        _jtag.tick(2'b00);
        repeat(5/*32*/) begin
            @(posedge _jtag.tck);
            $display("%t TDO:%b", $time, _jtag.tdo);
        end

        phase.drop_objection(this);
    endtask: run_phase

endclass

