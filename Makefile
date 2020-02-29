bold   := $(shell tput bold)
red    := $(shell tput setaf 1)
green  := $(shell tput setaf 2)
yellow := $(shell tput setaf 3)
normal := $(shell tput sgr0)


define build_block
	@echo "$(bold)$(green)-----------------------------------------------------$(normal)"
	@echo "$(bold)$(green)                     $1 $(normal)"
	@echo "$(bold)$(green)-----------------------------------------------------$(normal)"
	@echo ""
	cd blocks/$1/test && make clean && make
endef

define test_block
	@echo "$(bold)$(green)-----------------------------------------------------$(normal)"
	@echo "$(bold)$(green)                     $1 $(normal)"
	@echo "$(bold)$(green)-----------------------------------------------------$(normal)"
	@echo ""
	cd blocks/$1/test && make run_test
endef

.PHONY: build
build:
	$(call build_block,AddCmp)
	$(call build_block,Incr)

.PHONY: test_AddCmp
test_AddCmp:
	$(call test_block,AddCmp)

