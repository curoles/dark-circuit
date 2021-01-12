class TestBypass extends uvm_test;

    `uvm_component_utils(TestBypass);

    Env _env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    function void build_phase(uvm_phase phase);
        Tester::type_id::set_type_override(Tester::get_type());
        _env = Env::type_id::create("_env", this);
    endfunction: build_phase

endclass
