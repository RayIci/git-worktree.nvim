NVIM ?= nvim
STYLUA ?= stylua

.PHONY: test test-integration fmt fmt-check helptags

## test: run the headless test suite (FILTER=name to run some spec files)
test:
	$(NVIM) --headless -u NONE -l tests/run.lua $(FILTER)

## test-integration: run the integration specs against the plugins on 'packpath'
test-integration:
	$(NVIM) --headless -u NONE -l tests/run.lua --integration $(FILTER)

## fmt: format the Lua sources
fmt:
	$(STYLUA) lua tests

## fmt-check: check formatting without changing files
fmt-check:
	$(STYLUA) --check lua tests

## helptags: build doc/tags for :help git-worktree
helptags:
	$(NVIM) --headless -u NONE -c 'helptags doc' -c q
