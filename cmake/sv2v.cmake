# @brief Check that a design converts to Verilog-2005 with sv2v, the input for synthesis.
#
# Use of sv2v is controlled by cache variable DARK_CIRCUIT_USE_SV2V (AUTO, ON or OFF).

dc_use_tool(SV2V sv2v)

# dc_add_sv2v_check(<name> TOP <module> FLISTS <flist>...)
#
# Add CTest test <name>.sv2v (cmake -P sv2v_check.cmake): sv2v converts the files of
# FLISTS with top module TOP and writes <name>.sv2v.v in the build directory (the input
# for Yosys later), then Verilator elaborates that file (--lint-only): the test fails
# when sv2v fails, for example on syntax it does not support, or when the design is not
# complete (a module or a port is missing). Without Verilator only sv2v runs.
# Labels: sv2v and labels of dc_test_labels(). Does nothing if sv2v is not used.
function(dc_add_sv2v_check NAME)
    if(NOT DARK_CIRCUIT_SV2V)
        return()
    endif()
    cmake_parse_arguments(S "" "TOP" "FLISTS" ${ARGN})
    if(NOT S_TOP OR NOT S_FLISTS)
        message(FATAL_ERROR "sv2v check ${NAME}: TOP and FLISTS are required")
    endif()
    set(files)
    foreach(flist IN LISTS S_FLISTS)
        dc_read_flist(flist_files ${flist})
        list(APPEND files ${flist_files})
    endforeach()
    set(verilator)
    if(DARK_CIRCUIT_VERILATOR)
        set(verilator ${VERILATOR_BIN})
    endif()
    set(test ${NAME}.sv2v)
    add_test(NAME ${test}
        COMMAND ${CMAKE_COMMAND} -D SV2V=${SV2V_BIN} -D VERILATOR=${verilator}
                -D TOP=${S_TOP} -D OUT=${CMAKE_CURRENT_BINARY_DIR}/${test}.v
                -P ${PROJECT_SOURCE_DIR}/cmake/sv2v_check.cmake -- ${files})
    dc_test_labels(labels)
    set_tests_properties(${test} PROPERTIES LABELS "sv2v;${labels}")
endfunction()
