set(VERILATOR_PARAMS_${TEST_NAME}
    -sv
    -O3 -Wall -Wno-lint --assert
    --cc --compiler gcc
    --exe ${TB_MAIN_CPP} --clk clk
    --Mdir obj_dir_${TEST_NAME}
    ${TB_FLIST}
    -CFLAGS "-I${DARKCIRCUIT_SOURCE_DIR}/tools"
    -CFLAGS "-O3"
    --top-module ${TB_TOP} ${TB_TOP_FILE}
    ${DARKCIRCUIT_SOURCE_DIR}/tools/eda/verilator/verilator_tick.cpp
)

add_custom_target(
    EXE_VTB_${TEST_NAME} ALL
    COMMAND verilator ${VERILATOR_PARAMS_${TEST_NAME}}
    COMMAND make -C ${CMAKE_CURRENT_BINARY_DIR}/obj_dir_${TEST_NAME} -j -f V${TB_TOP}.mk V${TB_TOP}
)

add_test(NAME test_${TEST_NAME}
    COMMAND ${CMAKE_CURRENT_BINARY_DIR}/obj_dir_${TEST_NAME}/V${TB_TOP}
)

