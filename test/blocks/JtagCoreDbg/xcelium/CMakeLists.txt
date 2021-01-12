# Author: Igor Lesik 2020

enable_testing()

set(TB_TOP TbTop)
set(TB_TOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/TbTop.sv)

set(TEST_NAME JtagCoreDbg)

set(TB_FLIST
    -incdir ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/macros
    -F ${DARKCIRCUIT_SOURCE_DIR}/rtl/blocks/blocks.flist
    -F ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/parts/parts.flist
    -F ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/gates/generic/generic.flist
    -F ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/sim/sim.flist
    -F ${CMAKE_CURRENT_SOURCE_DIR}/tb.flist
)
include(${DARKCIRCUIT_SOURCE_DIR}/tools/eda/xcelium/simple_test.cmake)
