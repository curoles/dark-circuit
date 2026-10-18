# @brief Icarus Verilog tests.
#
# Icarus is 4-state event driven simulator, good for small tests:
# it shows X and Z values that 2-state simulators hide.

dc_use_tool(ICARUS iverilog vvp)

# dc_add_icarus_build(<name> TOP <module> TB <tb.sv>
#                     [FLISTS <flist>...] [DEFINES <macro>...])
#
# Compile testbench <tb.sv> and files from <flist>s with Icarus Verilog into
# simulation <name>.icarus (target and .vvp file). Tests that run it are added with
# dc_add_icarus_run(), so one build serves many tests.
# Does nothing if Icarus is not used.
function(dc_add_icarus_build NAME)
    if(NOT DARK_CIRCUIT_ICARUS)
        return()
    endif()
    dc_parse_test_args(${NAME} ${ARGN})

    set(defines)
    foreach(define IN LISTS T_DEFINES)
        list(APPEND defines -D${define})
    endforeach()

    set(sim ${NAME}.icarus)
    set(vvp ${CMAKE_CURRENT_BINARY_DIR}/${sim}.vvp)
    add_custom_command(
        OUTPUT ${vvp}
        COMMAND ${IVERILOG_BIN} -g2012 -Wall ${defines} -s ${T_TOP} -o ${vvp} ${T_SOURCES}
        DEPENDS ${T_SOURCES}
        COMMENT "Icarus Verilog: compiling ${sim}"
        VERBATIM
    )
    add_custom_target(${sim} ALL DEPENDS ${vvp})
    # Command of the tests, a property of the target: tests of any directory can run it.
    set_target_properties(${sim} PROPERTIES DC_RUN_COMMAND "${VVP_BIN};-n;${vvp}")
endfunction()

# dc_add_icarus_run(<test> BUILD <name> [ARGS <arg>...] [LABELS <label>...]
#           [OUTPUT <regex>])
#
# Add CTest test <test>.icarus with label icarus, labels of dc_test_labels() and LABELS:
# it runs simulation <name>.icarus of dc_add_icarus_build() with ARGS;
# with OUTPUT the test also fails when the output does not match <regex>.
# Testbench fails the test with $fatal, then vvp exit code is 1.
# Does nothing if Icarus is not used.
function(dc_add_icarus_run TEST)
    if(NOT DARK_CIRCUIT_ICARUS)
        return()
    endif()
    dc_parse_run_args(${TEST} ${ARGN})

    get_target_property(command ${R_BUILD}.icarus DC_RUN_COMMAND)
    set(test ${TEST}.icarus)
    dc_run_command(test_command ${command} ${R_ARGS})
    add_test(NAME ${test} COMMAND ${test_command})
    dc_test_labels(labels)
    set(test_labels icarus ${labels} ${R_LABELS})
    set_tests_properties(${test} PROPERTIES LABELS "${test_labels}")
endfunction()

# dc_add_icarus_test(<name> TOP <module> TB <tb.sv>
#                    [FLISTS <flist>...] [DEFINES <macro>...] [ARGS <arg>...])
#
# Build simulation <name>.icarus and add test <name>.icarus that runs it with ARGS:
# dc_add_icarus_build() and dc_add_icarus_run() for a testbench with one test.
function(dc_add_icarus_test NAME)
    dc_parse_test_args(${NAME} ${ARGN})
    dc_add_icarus_build(${NAME} TOP ${T_TOP} TB ${T_TB} FLISTS ${T_FLISTS} DEFINES ${T_DEFINES})
    dc_add_icarus_run(${NAME} BUILD ${NAME} ARGS ${T_ARGS})
endfunction()
