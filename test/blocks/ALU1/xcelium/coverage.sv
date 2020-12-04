module Coverage #(
    parameter WIDTH = 64
)(
    Alu1Bfm bfm
);

    Alu1Op op;

    // Cadence help UI: cdnshelp.
    // Add `-coverage A` to elaboration.
    // Default coverage directory with .ucd is cov_work.
    // Viewer tool: imc
    //
    covergroup OpCov;
        coverpoint op {
            bins arithm[] = {[ALU1_OP_TRANSFER:ALU1_OP_TRANSFER2]};
            bins logics[] = {[ALU1_OP_AND:ALU1_OP_NOT]};
        }
    endgroup

    OpCov op_cov;
    //zeros_or_ones_on_ops c_00_FF;

    initial begin: coverage
        op_cov = new();
        //c_00_FF = new();
   
        forever begin: sampling
            @(negedge bfm.clk);
            op = bfm.op;
            op_cov.sample();
            //c_00_FF.sample();
        end: sampling
    end: coverage


endmodule: Coverage
