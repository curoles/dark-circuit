# PackedSaturate on PackedAdd against clamped lane arithmetic, and PackedPkg::lane_tops: lanes
# of 8 bits exhaustive (every pair of bytes, add and subtract, signed and unsigned), lanes of
# 16 and 32 bits edge values and random words; PACKED_FLISTS: test/numeric/CMakeLists.txt.
dc_add_mainsim_test(numeric_packed_saturate TOP TbPackedSaturate TB tb_packed_saturate.sv
                    FLISTS ${PACKED_FLISTS})
