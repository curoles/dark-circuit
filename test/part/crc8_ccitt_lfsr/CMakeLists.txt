dc_add_mainsim_test(part_crc8_ccitt_lfsr TOP TbCrc8CcittLfsr TB tb_crc8_ccitt_lfsr.sv
                    FLISTS ${DARK_CIRCUIT_RTL_LIB}/gate/generic/gate_generic.flist
                           ${DARK_CIRCUIT_RTL_LIB}/sim/sim.flist
                           ${DARK_CIRCUIT_RTL_LIB}/part/part.flist)
