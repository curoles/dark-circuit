# PackedMinMax on PackedAdd's a - b against lane minimum and maximum: lanes of 8 bits
# exhaustive (every pair of bytes, minimum and maximum, signed and unsigned), lanes of 16 and
# 32 bits edge values and random words; PACKED_FLISTS: test/numeric/CMakeLists.txt.
dc_add_mainsim_test(numeric_packed_min_max TOP TbPackedMinMax TB tb_packed_min_max.sv
                    FLISTS ${PACKED_FLISTS})
