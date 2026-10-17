# @brief Checks that files generated from design configurations are up to date.
#
# tools/config_gen.py needs Python 3 with modules yaml and jinja2.
# Use of Python is controlled by cache variable DARK_CIRCUIT_USE_PYTHON (AUTO, ON or OFF).

dc_use_tool(PYTHON PYTHON3=python3)

if(DARK_CIRCUIT_PYTHON)
    execute_process(COMMAND ${PYTHON3_BIN} -c "import yaml, jinja2"
                    RESULT_VARIABLE result OUTPUT_QUIET ERROR_QUIET)
    if(NOT result EQUAL 0)
        string(TOUPPER "${DARK_CIRCUIT_USE_PYTHON}" mode)
        if(mode STREQUAL "ON")
            message(FATAL_ERROR "PYTHON: modules yaml and jinja2 are required (python3-yaml, python3-jinja2)")
        endif()
        message(STATUS "PYTHON: modules yaml and jinja2 not found (python3-yaml, python3-jinja2), config checks are disabled")
        set(DARK_CIRCUIT_PYTHON FALSE)
    endif()
endif()

# dc_add_config_check(<name> CONFIG <config.yaml>)
#
# Add CTest test <name>.config that runs tools/config_gen.py --check: it fails when
# a file generated from <config.yaml> is missing or out of date, then run `make config`.
# Labels: config and labels of dc_test_labels(). Does nothing if Python is not used.
function(dc_add_config_check NAME)
    if(NOT DARK_CIRCUIT_PYTHON)
        return()
    endif()
    cmake_parse_arguments(C "" "CONFIG" "" ${ARGN})
    if(NOT C_CONFIG)
        message(FATAL_ERROR "Config check ${NAME}: CONFIG is required")
    endif()
    set(test ${NAME}.config)
    add_test(NAME ${test}
        COMMAND ${PYTHON3_BIN} ${PROJECT_SOURCE_DIR}/tools/config_gen.py
                --root ${PROJECT_SOURCE_DIR} ${C_CONFIG} --check)
    dc_test_labels(labels)
    set_tests_properties(${test} PROPERTIES LABELS "config;${labels}")
endfunction()
