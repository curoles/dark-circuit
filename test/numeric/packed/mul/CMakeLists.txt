# PackedMul against lane products: byte modes exhaustive (every byte pair in every position,
# all sign modes), 16 x 16 edge values and random words; PACKED_FLISTS:
# test/numeric/CMakeLists.txt.
dc_add_mainsim_test(numeric_packed_mul TOP TbPackedMul TB tb_packed_mul.sv
                    FLISTS ${PACKED_FLISTS})
