# @brief Icarus Verilog tests.
#
# Icarus is 4-state event driven simulator, good for small tests:
# it shows X and Z values that 2-state simulators hide.

dc_use_tool(ICARUS iverilog vvp)

# dc_add_icarus_test(<name> TOP <module> TB <tb.sv>
#                    [FLISTS <flist>...] [DEFINES <macro>...] [ARGS <arg>...])
#
# Compile testbench <tb.sv> and files from <flist>s with Icarus Verilog
# and add CTest test <name>.icarus with label icarus and labels of dc_test_labels().
# The test runs vvp with ARGS.
# Testbench fails the test with $fatal, then vvp exit code is 1.
# Does nothing if Icarus is not used.
function(dc_add_icarus_test NAME)
    if(NOT DARK_CIRCUIT_ICARUS)
        return()
    endif()
    dc_parse_test_args(${NAME} ${ARGN})

    set(defines)
    foreach(define IN LISTS T_DEFINES)
        list(APPEND defines -D${define})
    endforeach()

    set(test ${NAME}.icarus)
    set(vvp ${CMAKE_CURRENT_BINARY_DIR}/${test}.vvp)
    add_custom_command(
        OUTPUT ${vvp}
        COMMAND ${IVERILOG_BIN} -g2012 -Wall ${defines} -s ${T_TOP} -o ${vvp} ${T_SOURCES}
        DEPENDS ${T_SOURCES}
        COMMENT "Icarus Verilog: compiling ${test}"
        VERBATIM
    )
    add_custom_target(${test} ALL DEPENDS ${vvp})
    add_test(NAME ${test} COMMAND ${VVP_BIN} -n ${vvp} ${T_ARGS})
    dc_test_labels(labels)
    set(test_labels icarus ${labels})
    set_tests_properties(${test} PROPERTIES LABELS "${test_labels}")
endfunction()
