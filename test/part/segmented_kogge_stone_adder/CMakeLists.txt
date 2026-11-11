dc_add_mainsim_test(part_segmented_kogge_stone_adder TOP TbSegmentedKoggeStoneAdder
                    TB tb_segmented_kogge_stone_adder.sv
                    FLISTS ${DARK_CIRCUIT_RTL_LIB}/gate/generic/gate_generic.flist
                           ${DARK_CIRCUIT_RTL_LIB}/part/part.flist)
