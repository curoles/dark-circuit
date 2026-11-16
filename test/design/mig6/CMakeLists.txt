set(LIB  ${DARK_CIRCUIT_RTL_LIB})
set(MIG6 ${DARK_CIRCUIT_RTL_DESIGN}/mig6)

# Mig6 is a prototype (rtl/design/mig6/README.md). For now only its core, a copy of Mig3's
# (Mig6Core), with the checks a core without tests has: the generated configuration, sv2v,
# synthesis.

# Files generated from cfg/mig6_config.yaml are up to date.
dc_add_config_check(design_mig6 CONFIG ${MIG6}/cfg/mig6_config.yaml)

# Hardware files of Mig6Core: struct versions of the library, built from generic gates, the
# fp32 and packed blocks (one version: hybrid), RISC-V formats and encodings.
set(SYNTH_FLISTS ${LIB}/gate/generic/gate_generic.flist ${LIB}/part/part.flist
                 ${LIB}/block/block_struct.flist ${LIB}/numeric/numeric_struct.flist
                 ${LIB}/numeric/fp32/fp32.flist ${LIB}/numeric/packed/packed.flist
                 ${LIB}/riscv/riscv.flist ${MIG6}/mig6.flist)

# Mig6Core converts to Verilog-2005 with sv2v and elaborates.
dc_add_sv2v_check(design_mig6 TOP Mig6Core FLISTS ${SYNTH_FLISTS})

# Synthesis of Mig6Core: build target design_mig6.synth (make mig6_synth), not a test. The
# tag and data RAMs of the caches are memory macros in a chip: black boxes.
dc_add_yosys_synth(design_mig6 TOP Mig6Core FLISTS ${SYNTH_FLISTS}
                   BLACKBOX_RAM_MODULES CacheTagRam CacheDataRam)
