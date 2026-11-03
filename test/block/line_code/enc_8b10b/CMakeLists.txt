set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Enc8b10b with its halves Enc5b6b and Enc3b4b (no tests of their own); behavioral only.
dc_add_mainsim_test(block_enc_8b10b_behave TOP TbEnc8b10b
                    TB tb_enc_8b10b.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
