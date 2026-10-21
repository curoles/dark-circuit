# @brief Convert a design with sv2v and check that the result elaborates.
#
# cmake -D SV2V=<sv2v> [-D VERILATOR=<verilator>] -D TOP=<module> -D OUT=<file.v>
#       -D INCLUDE=<dir> -P sv2v_check.cmake -- <file>...
# sv2v converts <file>... with top module TOP into OUT, `include files are found in
# INCLUDE; then Verilator elaborates OUT
# (--lint-only, warnings are not errors): sv2v does not fail when a module is missing,
# it can not know where modules come from. Fails (cmake exit code not 0) when either
# step fails. Without VERILATOR only sv2v runs. See dc_add_sv2v_check() in sv2v.cmake.

set(files)
set(after_separator FALSE)
math(EXPR last "${CMAKE_ARGC} - 1")
foreach(i RANGE ${last})
    if(after_separator)
        list(APPEND files "${CMAKE_ARGV${i}}")
    elseif(CMAKE_ARGV${i} STREQUAL "--")
        set(after_separator TRUE)
    endif()
endforeach()
if(NOT SV2V OR NOT TOP OR NOT OUT OR NOT INCLUDE OR NOT files)
    message(FATAL_ERROR "sv2v_check.cmake: SV2V, TOP, OUT, INCLUDE and files after -- are required")
endif()

execute_process(
    COMMAND ${SV2V} -I${INCLUDE} --top=${TOP} --write=${OUT} ${files}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE  output
)
message("${output}")
if(NOT result STREQUAL "0")
    message(FATAL_ERROR "sv2v failed, exit code: ${result}")
endif()

if(VERILATOR)
    execute_process(
        COMMAND ${VERILATOR} --lint-only -Wno-fatal --top-module ${TOP} ${OUT}
        RESULT_VARIABLE result
        OUTPUT_VARIABLE output
        ERROR_VARIABLE  output
    )
    message("${output}")
    if(NOT result STREQUAL "0")
        message(FATAL_ERROR "Verilator can not elaborate ${OUT}, exit code: ${result}")
    endif()
endif()
