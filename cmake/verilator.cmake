# @brief Verilator tests.
#
# Verilator is 2-state cycle based simulator, fast for big designs.
# Tests need Verilator 5.0 or newer because they use --binary and --timing.

dc_use_tool(VERILATOR verilator)

if(DARK_CIRCUIT_VERILATOR)
    execute_process(COMMAND ${VERILATOR_BIN} --version OUTPUT_VARIABLE version_text)
    string(STRIP "${version_text}" version_text)
    string(REGEX MATCH "Verilator ([0-9]+)\\.([0-9]+)" version_match "${version_text}")
    if(version_match AND NOT CMAKE_MATCH_1 LESS 5)
        message(STATUS "VERILATOR: version ${CMAKE_MATCH_1}.${CMAKE_MATCH_2}")
    else()
        string(TOUPPER "${DARK_CIRCUIT_USE_VERILATOR}" mode)
        if(mode STREQUAL "ON")
            message(FATAL_ERROR "VERILATOR: version 5.0 or newer is required, found: ${version_text}")
        endif()
        message(STATUS "VERILATOR: version 5.0 or newer is needed, found: ${version_text}, VERILATOR tests are disabled")
        set(DARK_CIRCUIT_VERILATOR FALSE)
    endif()
endif()

# dc_add_verilator_build(<name> TOP <module> TB <tb.sv>
#                        [FLISTS <flist>...] [DEFINES <macro>...])
#
# Build testbench <tb.sv> and files from <flist>s with Verilator --binary --timing
# into simulation <name>.verilator (target and executable). Tests that run it are
# added with dc_add_verilator_run(), so one build serves many tests.
# Does nothing if Verilator is not used.
function(dc_add_verilator_build NAME)
    if(NOT DARK_CIRCUIT_VERILATOR)
        return()
    endif()
    dc_parse_test_args(${NAME} ${ARGN})

    set(defines)
    foreach(define IN LISTS T_DEFINES)
        list(APPEND defines -D${define})
    endforeach()

    set(sim ${NAME}.verilator)
    set(dir ${CMAKE_CURRENT_BINARY_DIR}/${sim}.dir)
    set(exe ${dir}/${sim})
    # -Wno-DECLFILENAME: file names are lower case, cell module names are upper case.
    add_custom_command(
        OUTPUT ${exe}
        COMMAND ${VERILATOR_BIN} --binary --timing -Wall -Wno-DECLFILENAME
                -D${DARK_CIRCUIT_TYPE_PARAM_MACRO}
                ${defines} --top-module ${T_TOP} -Mdir ${dir} -o ${sim} ${T_SOURCES}
        DEPENDS ${T_SOURCES}
        COMMENT "Verilator: building ${sim}"
        VERBATIM
    )
    add_custom_target(${sim} ALL DEPENDS ${exe})
    # Command of the tests, a property of the target: tests of any directory can run it.
    set_target_properties(${sim} PROPERTIES DC_RUN_COMMAND "${exe}")
endfunction()

# dc_add_verilator_run(<test> BUILD <name> [ARGS <arg>...] [LABELS <label>...]
#              [OUTPUT <regex>])
#
# Add CTest test <test>.verilator with label verilator, labels of dc_test_labels() and LABELS:
# it runs simulation <name>.verilator of dc_add_verilator_build() with ARGS;
# with OUTPUT the test also fails when the output does not match <regex>.
# Testbench fails the test with $fatal, then the simulation exit code is not 0.
# Does nothing if Verilator is not used.
function(dc_add_verilator_run TEST)
    if(NOT DARK_CIRCUIT_VERILATOR)
        return()
    endif()
    dc_parse_run_args(${TEST} ${ARGN})

    get_target_property(command ${R_BUILD}.verilator DC_RUN_COMMAND)
    set(test ${TEST}.verilator)
    dc_run_command(test_command ${command} ${R_ARGS})
    add_test(NAME ${test} COMMAND ${test_command})
    dc_test_labels(labels)
    set(test_labels verilator ${labels} ${R_LABELS})
    set_tests_properties(${test} PROPERTIES LABELS "${test_labels}")
endfunction()

# dc_add_verilator_test(<name> TOP <module> TB <tb.sv>
#                       [FLISTS <flist>...] [DEFINES <macro>...] [ARGS <arg>...])
#
# Build simulation <name>.verilator and add test <name>.verilator that runs it with
# ARGS: dc_add_verilator_build() and dc_add_verilator_run() for a testbench with one test.
function(dc_add_verilator_test NAME)
    dc_parse_test_args(${NAME} ${ARGN})
    dc_add_verilator_build(${NAME} TOP ${T_TOP} TB ${T_TB} FLISTS ${T_FLISTS} DEFINES ${T_DEFINES})
    dc_add_verilator_run(${NAME} BUILD ${NAME} ARGS ${T_ARGS})
endfunction()
