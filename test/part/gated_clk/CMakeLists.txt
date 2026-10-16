dc_add_mainsim_test(part_gated_clk TOP TbGatedClk TB tb_gated_clk.sv
                    FLISTS ${DARK_CIRCUIT_RTL_LIB}/gate/generic/gate_generic.flist
                           ${DARK_CIRCUIT_RTL_LIB}/part/part.flist)
