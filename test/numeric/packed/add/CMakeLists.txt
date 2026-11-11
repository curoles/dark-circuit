# PackedAdd and PackedPkg's helpers against lane arithmetic: lanes of 8 bits exhaustive (every
# pair of bytes, add and subtract), lanes of 16 and 32 bits edge values and random words;
# PACKED_FLISTS: test/numeric/CMakeLists.txt.
dc_add_mainsim_test(numeric_packed_add TOP TbPackedAdd TB tb_packed_add.sv FLISTS ${PACKED_FLISTS})
