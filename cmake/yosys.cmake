# @brief Synthesis of a design with Yosys: build targets per design, not tests.
#
# Use of Yosys is controlled by cache variable DARK_CIRCUIT_USE_YOSYS (AUTO, ON or OFF).
# Yosys reads the Verilog-2005 that sv2v writes, so synthesis needs sv2v too.

dc_use_tool(YOSYS yosys)

# _dc_yosys_target(<name> <tech> <target> <liberty> <top> <file>...)
#
# Target <target> for dc_add_yosys_synth(): sv2v converts <file>... with top module <top>,
# Yosys runs cmake/yosys_synth.ys.in with cmake/yosys_tech_<tech>.ys.in, both filled in
# into the output directory <target>/ (synth.ys, tech.ys). For a technology with a
# liberty file (not generic), report.txt has area and longest path (synth_report.cmake);
# building the target prints it, also when nothing changed.
function(_dc_yosys_target NAME TECH TARGET LIBERTY TOP)
    set(files ${ARGN})
    set(dir ${CMAKE_CURRENT_BINARY_DIR}/${TARGET})
    set(SYNTH_NAME ${NAME})
    set(SYNTH_TECH ${TECH})
    set(SYNTH_INPUT ${dir}/${NAME}.sv2v.v)
    set(SYNTH_TOP ${TOP})
    set(SYNTH_LIBERTY ${LIBERTY})
    set(SYNTH_TECH_SCRIPT ${dir}/tech.ys)
    set(SYNTH_ARGS)
    if(NOT TECH STREQUAL "generic")
        set(SYNTH_ARGS -flatten)
    endif()
    configure_file(${PROJECT_SOURCE_DIR}/cmake/yosys_synth.ys.in ${dir}/synth.ys @ONLY)
    configure_file(${PROJECT_SOURCE_DIR}/cmake/yosys_tech_${TECH}.ys.in ${dir}/tech.ys @ONLY)

    add_custom_command(
        OUTPUT ${SYNTH_INPUT}
        COMMAND ${SV2V_BIN} -I${DARK_CIRCUIT_RTL_MACRO} --top=${TOP} --write=${SYNTH_INPUT}
                ${files}
        DEPENDS ${files} ${DARK_CIRCUIT_ASSERT_SVH}
        COMMENT "sv2v: ${NAME}"
        VERBATIM)

    set(outputs ${dir}/netlist.v ${dir}/stat.txt)
    set(report_command)
    set(show ${CMAKE_COMMAND} -E echo "${NAME} (${TECH}): netlist.v, stat.txt in ${dir}")
    if(NOT TECH STREQUAL "generic")
        list(APPEND outputs ${dir}/report.txt)
        set(report_command COMMAND ${CMAKE_COMMAND} -D NAME=${NAME} -D TECH=${TECH} -D DIR=${dir}
                                   -P ${PROJECT_SOURCE_DIR}/cmake/synth_report.cmake)
        set(show ${CMAKE_COMMAND} -E cat ${dir}/report.txt)
    endif()
    # Old outputs are removed first, so a failed synthesis leaves no netlist that looks current.
    add_custom_command(
        OUTPUT ${outputs}
        COMMAND ${CMAKE_COMMAND} -E rm -f netlist.v stat.txt report.txt
        COMMAND ${YOSYS_BIN} -q -l yosys.log -s synth.ys
        ${report_command}
        WORKING_DIRECTORY ${dir}
        DEPENDS ${SYNTH_INPUT} ${dir}/synth.ys ${dir}/tech.ys
                ${PROJECT_SOURCE_DIR}/cmake/synth_report.cmake
        COMMENT "Yosys: synthesis of ${NAME} (${TECH}), log ${dir}/yosys.log"
        VERBATIM)
    add_custom_target(${TARGET} COMMAND ${show} DEPENDS ${outputs} VERBATIM)
endfunction()

# dc_add_yosys_synth(<name> TOP <module> FLISTS <flist>...)
#
# Add targets, not built by default (make <design>_synth [TECH=<tech>]):
#   <name>.synth         generic: Yosys gates; checks, cells of every module
#   <name>.synth_sky130  sky130 cells: checks, area, longest path (report.txt, printed)
# Each: sv2v converts the files of FLISTS with top module TOP, Yosys runs the script
# cmake/yosys_synth.ys.in with cmake/yosys_tech_<tech>.ys.in, filled in for this design.
# Outputs in <name>.synth/ or <name>.synth_sky130/ of the build directory: synth.ys and
# tech.ys (the scripts that ran), <name>.sv2v.v, netlist.v, stat.txt, yosys.log and, for
# sky130, report.txt. A target fails when synthesis fails, finds a latch or a structural
# problem; synth_sky130 also fails when the sky130 liberty is not available.
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

    _dc_yosys_target(${NAME} generic ${NAME}.synth "" ${Y_TOP} ${files})

    dc_sky130()
    if(DARK_CIRCUIT_SKY130)
        _dc_yosys_target(${NAME} sky130 ${NAME}.synth_sky130 ${SKY130_FILE} ${Y_TOP} ${files})
    else()
        add_custom_target(${NAME}.synth_sky130
            COMMAND ${CMAKE_COMMAND} -E echo "sky130 liberty not available, see DARK_CIRCUIT_USE_SKY130"
            COMMAND ${CMAKE_COMMAND} -E false
            VERBATIM)
    endif()
endfunction()
