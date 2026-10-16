class TestBypass extends uvm_test;

    `uvm_component_utils(TestBypass)

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

        // After reset IR=IDCODE, if we set state=Shift-DR then next
        // 32 TDOs will tell IDCODE.
        $display("%t Set state=Shift-DR", $time);
        _jtag.go_shift_dr();
        repeat(32) begin
            @(posedge _jtag.tck);
            $display("%t TDO:%b", $time, _jtag.tdo);
        end

        _jtag.do_reset_5tms();

        $display("%t Set state=Shift-IR", $time);
        _jtag.go_shift_ir();
        $display("%t Set IR=IDCODE", $time);
        _jtag.do_ir_idcode();
        $display("%t Set state=Shift-DR", $time);
        _jtag.tick4(2'b10,2'b10,2'b00,2'b00); // Update-IR -> Shift-DR
        repeat(32) begin
            @(posedge _jtag.tck);
            $display("%t TDO:%b", $time, _jtag.tdo);
        end

        _jtag.do_reset_5tms();

        $display("%t Set state=Shift-IR", $time);
        _jtag.go_shift_ir();
        $display("%t Set IR=BYPASS", $time);
        _jtag.do_ir_bypass();
        $display("%t Set state=Shift-DR", $time);
        _jtag.tick4(2'b10,2'b10,2'b00,2'b00); // Update-IR -> Shift-DR
        repeat(8) begin
            _jtag.tick(2'b00);
            $display("%t TDO:%b", $time, _jtag.tdo);
            assert(_jtag.tdo == _jtag.tdi);
            _jtag.tick(2'b01);
            $display("%t TDO:%b", $time, _jtag.tdo);
            assert(_jtag.tdo == _jtag.tdi);
        end

        phase.drop_objection(this);
    endtask: run_phase

endclass
