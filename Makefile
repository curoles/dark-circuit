bold   := $(shell tput bold)
red    := $(shell tput setaf 1)
green  := $(shell tput setaf 2)
yellow := $(shell tput setaf 3)
normal := $(shell tput sgr0)



.PHONY: build
build:
	@echo "$(bold)$(green)---------- AddCmp ---------$(normal)"
	cd blocks/AddCmp/test && make clean && make
	@echo "$(bold)$(green)---------- Incr ---------$(normal)"
	cd blocks/Incr/test && make clean && make
