# Author: Igor Lesik 2021

enable_testing()

set(TB_TOP TbTop)
set(TB_TOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/TbTop.sv)
set(TB_MAIN_CPP ${CMAKE_CURRENT_SOURCE_DIR}/sim_main.cpp)

set(TEST_NAME BarrelShifter)
set(TB_FLIST
    -F ${DARKCIRCUIT_SOURCE_DIR}/rtl/blocks/blocks.flist
    -F ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/parts/parts.flist
    -F ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/gates/generic/generic.flist
    -y ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/macros
)
include(${DARKCIRCUIT_SOURCE_DIR}/tools/eda/verilator/simple_test.cmake)