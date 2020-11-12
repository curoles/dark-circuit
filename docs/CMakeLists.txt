file(GLOB_RECURSE rtl_files
    ${DARKCIRCUIT_SOURCE_DIR}/rtl/*.sv
    ${DARKCIRCUIT_SOURCE_DIR}/rtl/*.flist
)

set(flists
    -F ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/gates/cmos/cmos.flist
    ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/gates/builtin/builtin.flist
    ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/gates/generic/generic.flist
    ${DARKCIRCUIT_SOURCE_DIR}/rtl/lib/parts/parts.flist
)

add_custom_command(
    OUTPUT index.html
    COMMAND veridoc.py -s --inline --toc-sidebar -o index.html ${flists}
    DEPENDS ${rtl_files}
)

add_custom_target(
    docs ALL
    COMMAND echo "Build docs"
    DEPENDS index.html
)

add_custom_target(
    copy_docs_index_to_src ALL
    COMMAND ${CMAKE_COMMAND} -E copy ${DARKCIRCUIT_BINARY_DIR}/docs/index.html ${DARKCIRCUIT_SOURCE_DIR}/docs/index.html
    DEPENDS docs
)
