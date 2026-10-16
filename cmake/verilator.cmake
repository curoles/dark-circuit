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

# dc_add_verilator_test(<name> TOP <module> TB <tb.sv>
#                       [FLISTS <flist>...] [DEFINES <macro>...])
#
# Build testbench <tb.sv> and files from <flist>s with Verilator --binary --timing
# and add CTest test <name>.verilator with label verilator and labels of dc_test_labels().
# Testbench fails the test with $fatal, then the simulation exit code is not 0.
# Does nothing if Verilator is not used.
function(dc_add_verilator_test NAME)
    if(NOT DARK_CIRCUIT_VERILATOR)
        return()
    endif()
    dc_parse_test_args(${NAME} ${ARGN})

    set(defines)
    foreach(define IN LISTS T_DEFINES)
        list(APPEND defines -D${define})
    endforeach()

    set(test ${NAME}.verilator)
    set(dir ${CMAKE_CURRENT_BINARY_DIR}/${test}.dir)
    set(exe ${dir}/${test})
    # -Wno-DECLFILENAME: file names are lower case, cell module names are upper case.
    add_custom_command(
        OUTPUT ${exe}
        COMMAND ${VERILATOR_BIN} --binary --timing -Wall -Wno-DECLFILENAME
                ${defines} --top-module ${T_TOP} -Mdir ${dir} -o ${test} ${T_SOURCES}
        DEPENDS ${T_SOURCES}
        COMMENT "Verilator: building ${test}"
        VERBATIM
    )
    add_custom_target(${test} ALL DEPENDS ${exe})
    add_test(NAME ${test} COMMAND ${exe})
    dc_test_labels(labels)
    set(test_labels verilator ${labels})
    set_tests_properties(${test} PROPERTIES LABELS "${test_labels}")
endfunction()
