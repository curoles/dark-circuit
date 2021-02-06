# Author: Igor Lesik 2020

enable_testing()

set(TB_TOP TbTop)
set(TB_TOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/TbTop.sv)
set(TB_MAIN_CPP ${CMAKE_CURRENT_SOURCE_DIR}/sim_main.cpp)
set(TB_CPP_FILES
    ${DARKCIRCUIT_SOURCE_DIR}/rtl/blocks/JtagCoreDbg/cpp/OocdRemoteBitbang.cpp
)

set(TEST_NAME Mig1CPU)
set(TB_FLIST
    -F ${DARKCIRCUIT_SOURCE_DIR}/rtl/blocks/blocks.flist
    -F ${DARKCIRCUIT_SOURCE_DIR}/rtl/designs/mig1/mig1.flist
    -y ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/macros
    ${DARKCIRCUIT_SOURCE_DIR}/rtl/blocks/JtagCoreDbg/rtl/SimDpiJtag.sv
)
include(${DARKCIRCUIT_SOURCE_DIR}/tools/eda/verilator/simple_test.cmake)
