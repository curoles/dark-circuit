# @brief Run a command, check its exit code and output.
#
# cmake [-D EXIT_CODE=<n>] [-D OUTPUT=<regex>] [-D TIMEOUT=<seconds>]
#       -P run_check.cmake -- <command> [<arg>...]
# Fails (cmake exit code not 0) when the command exit code is not EXIT_CODE (default 0),
# its output (stdout and stderr) does not match OUTPUT (if not empty), or it runs
# longer than TIMEOUT (if given). CTest alone checks either exit code or output.
# The command comes after `--`: arguments of cmake after -P <script> go to the script.

set(command)
set(after_separator FALSE)
math(EXPR last "${CMAKE_ARGC} - 1")
foreach(i RANGE ${last})
    if(after_separator)
        list(APPEND command "${CMAKE_ARGV${i}}")
    elseif(CMAKE_ARGV${i} STREQUAL "--")
        set(after_separator TRUE)
    endif()
endforeach()
if(NOT command)
    message(FATAL_ERROR "run_check.cmake: no command after --")
endif()
if(NOT DEFINED EXIT_CODE)
    set(EXIT_CODE 0)
endif()
set(timeout)
if(TIMEOUT)
    set(timeout TIMEOUT ${TIMEOUT})
endif()

execute_process(
    COMMAND ${command}
    ${timeout}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE  output
)
message("${output}")
if(NOT result STREQUAL "${EXIT_CODE}")
    message(FATAL_ERROR "exit code: ${result}, expected: ${EXIT_CODE}")
endif()
if(NOT OUTPUT STREQUAL "" AND NOT output MATCHES "${OUTPUT}")
    message(FATAL_ERROR "output does not match: ${OUTPUT}")
endif()
