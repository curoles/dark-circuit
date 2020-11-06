# Author: Igor Lesik 2020

enable_testing()

set(TB_TOP TbTop)
set(TB_TOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/TbTop.sv)
set(TB_MAIN_CPP ${CMAKE_CURRENT_SOURCE_DIR}/sim_main.cpp)

set(TEST_NAME GenericGates)
set(TB_FLIST -F ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/gates/generic/generic.flist)
include(${DARKCIRCUIT_SOURCE_DIR}/tools/eda/verilator/simple_test.cmake)

set(TEST_NAME CmosGates)
set(TB_FLIST -F ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/gates/cmos/cmos.flist)
include(${DARKCIRCUIT_SOURCE_DIR}/tools/eda/verilator/simple_test.cmake)

set(TEST_NAME BuiltinGates)
set(TB_FLIST -F ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/gates/builtin/builtin.flist)
include(${DARKCIRCUIT_SOURCE_DIR}/tools/eda/verilator/simple_test.cmake)

