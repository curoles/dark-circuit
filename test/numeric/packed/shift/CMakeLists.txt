# PackedShift against lane shifts as RISC-V P defines them: lanes of 8 bits exhaustive (every
# byte, every amount 0 to 31, left, logical and arithmetic right), lanes of 16 and 32 bits
# edge values with every amount and random words; PACKED_FLISTS: test/numeric/CMakeLists.txt.
dc_add_mainsim_test(numeric_packed_shift TOP TbPackedShift TB tb_packed_shift.sv
                    FLISTS ${PACKED_FLISTS})
