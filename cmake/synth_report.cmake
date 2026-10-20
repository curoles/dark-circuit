# @brief Summary of a technology synthesis: area, cells, longest path.
#
# cmake -D NAME=<name> -D TECH=<tech> -D DIR=<output dir> -P synth_report.cmake
# Reads DIR/stat.txt (Yosys stat -liberty) and DIR/yosys.log (ABC stime), writes
# DIR/report.txt. Fails when a value is missing (a changed Yosys output format).
# The delay is ABC's estimate: no wires, no clock-to-Q and setup of the flip-flops.

if(NOT NAME OR NOT TECH OR NOT DIR)
    message(FATAL_ERROR "synth_report.cmake: NAME, TECH and DIR are required")
endif()
file(READ ${DIR}/stat.txt stat)
file(READ ${DIR}/yosys.log log)

# The design is flattened: one module in stat.txt, one ABC run with one delay report.
# More means the numbers would be of some module, not of the design.
string(REGEX MATCHALL "Chip area for module '[^']*': [0-9]+" areas "${stat}")
string(REGEX MATCHALL "Delay = *[0-9]+" delays "${log}")
list(LENGTH areas n_areas)
list(LENGTH delays n_delays)
if(NOT n_areas EQUAL 1 OR NOT n_delays EQUAL 1)
    message(FATAL_ERROR "synth_report: design not flattened: ${n_areas} modules in "
                        "${DIR}/stat.txt, ${n_delays} delay reports in ${DIR}/yosys.log")
endif()
string(REGEX MATCH "Chip area for module '[^']*': ([0-9]+)(\\.([0-9]))?" _ "${stat}")
set(area ${CMAKE_MATCH_1})
if(CMAKE_MATCH_3 GREATER_EQUAL 5)                       # round to whole um2
    math(EXPR area "${area} + 1")
endif()
string(REGEX MATCH "\n +([0-9]+) +[0-9.E+]+ +cells\n" _ "${stat}")
set(cells ${CMAKE_MATCH_1})
set(ps)
if(delays)
    list(GET delays -1 ps)
    string(REGEX MATCH "[0-9]+$" ps "${ps}")
endif()
string(REGEX MATCHALL "Start-point = [^\n]*" paths "${log}")
set(from)
set(to)
if(paths)
    list(GET paths -1 path)
    string(REGEX MATCH "Start-point = [^ ]+ \\(([^)]*)\\)\\.  End-point = [^ ]+ \\(([^)]*)\\)" _ "${path}")
    set(from ${CMAKE_MATCH_1})
    set(to   ${CMAKE_MATCH_2})
endif()
if(NOT area OR NOT cells OR NOT ps OR NOT from OR NOT to)
    message(FATAL_ERROR "synth_report: values not found in ${DIR}/stat.txt or ${DIR}/yosys.log")
endif()

# Integer arithmetic: ns with one decimal, MHz rounded.
math(EXPR tenths "(${ps} + 50) / 100")
math(EXPR ns_int "${tenths} / 10")
math(EXPR ns_dec "${tenths} % 10")
math(EXPR mhz "(1000000 + ${ps} / 2) / ${ps}")

file(WRITE ${DIR}/report.txt
"${NAME} (${TECH}): area ${area} um2, ${cells} cells, longest path ${ns_int}.${ns_dec} ns (${mhz} MHz)
  path: ${from} -> ${to}
  ABC estimate: no wires, no clock-to-Q and setup; files in ${DIR}
")
