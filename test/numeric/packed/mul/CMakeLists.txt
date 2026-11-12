# PackedMul against lane products and group dot products: byte modes and the byte dot product
# exhaustive (every byte pair in every position, all sign modes, a random accumulator),
# 16 x 16 and the halfword dot product edge values and random words; PACKED_FLISTS:
# test/numeric/CMakeLists.txt.
dc_add_mainsim_test(numeric_packed_mul TOP TbPackedMul TB tb_packed_mul.sv
                    FLISTS ${PACKED_FLISTS})
