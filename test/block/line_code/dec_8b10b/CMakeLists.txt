set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Dec8b10b with its halves Dec6b5b and Dec4b3b (no tests of their own); behavioral only.
dc_add_mainsim_test(block_dec_8b10b_behave TOP TbDec8b10b
                    TB tb_dec_8b10b.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
