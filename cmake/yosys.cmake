# @brief Synthesis of a design with Yosys: a build target per design, not a test.
#
# Use of Yosys is controlled by cache variable DARK_CIRCUIT_USE_YOSYS (AUTO, ON or OFF).
# Yosys reads the Verilog-2005 that sv2v writes, so synthesis needs sv2v too.

dc_use_tool(YOSYS yosys)

# dc_add_yosys_synth(<name> TOP <module> FLISTS <flist>...)
#
# Add target <name>.synth, not built by default (make <design>_synth): sv2v converts the
# files of FLISTS with top module TOP, Yosys synthesizes the result with the script
# cmake/yosys_synth.ys.in filled in for this design. Outputs in <name>.synth/ of the
# build directory: synth.ys (the script that ran), <name>.sv2v.v, netlist.v, stat.txt,
# yosys.log. The target fails when synthesis fails, finds a latch or a structural problem.
# It runs again only when a file of FLISTS or the template changes.
# Does nothing if Yosys or sv2v is not used.
function(dc_add_yosys_synth NAME)
    if(NOT DARK_CIRCUIT_YOSYS OR NOT DARK_CIRCUIT_SV2V)
        return()
    endif()
    cmake_parse_arguments(Y "" "TOP" "FLISTS" ${ARGN})
    if(NOT Y_TOP OR NOT Y_FLISTS)
        message(FATAL_ERROR "Synthesis ${NAME}: TOP and FLISTS are required")
    endif()
    set(files)
    foreach(flist IN LISTS Y_FLISTS)
        dc_read_flist(flist_files ${flist})
        list(APPEND files ${flist_files})
    endforeach()

    set(dir ${CMAKE_CURRENT_BINARY_DIR}/${NAME}.synth)
    set(SYNTH_INPUT ${dir}/${NAME}.sv2v.v)
    set(SYNTH_TOP ${Y_TOP})
    configure_file(${PROJECT_SOURCE_DIR}/cmake/yosys_synth.ys.in ${dir}/synth.ys @ONLY)

    add_custom_command(
        OUTPUT ${SYNTH_INPUT}
        COMMAND ${SV2V_BIN} --top=${Y_TOP} --write=${SYNTH_INPUT} ${files}
        DEPENDS ${files}
        COMMENT "sv2v: ${NAME}"
        VERBATIM)
    # Old outputs are removed first, so a failed synthesis leaves no netlist that looks current.
    add_custom_command(
        OUTPUT ${dir}/netlist.v ${dir}/stat.txt
        COMMAND ${CMAKE_COMMAND} -E rm -f netlist.v stat.txt
        COMMAND ${YOSYS_BIN} -q -l yosys.log -s synth.ys
        WORKING_DIRECTORY ${dir}
        DEPENDS ${SYNTH_INPUT} ${dir}/synth.ys
        COMMENT "Yosys: synthesis of ${NAME}, outputs in ${dir}"
        VERBATIM)
    add_custom_target(${NAME}.synth DEPENDS ${dir}/netlist.v ${dir}/stat.txt)
endfunction()
