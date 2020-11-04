#file(GLOB vlog_files . rtl/*.sv)

add_custom_command(
    OUTPUT index.html
    COMMAND veridoc.py -s --inline --toc-sidebar -o index.html ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/gates/cmos/Not.sv
    #DEPENDS ${vlog_files}
)

add_custom_target(
    docs ALL
    COMMAND echo "Build docs"
    COMMAND cp ${DARKCIRCUIT_BINARY_DIR}/docs/index.html ${DARKCIRCUIT_SOURCE_DIR}/docs/index.html
    DEPENDS index.html
)
